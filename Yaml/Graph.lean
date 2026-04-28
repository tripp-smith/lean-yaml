import Yaml.AST
import Yaml.Error

namespace Yaml

structure RepresentationDocument where
  directives : Array Directive := #[]
  root : YamlNode := .scalar ""
  leadingComments : Array Comment := #[]
  trailingComments : Array Comment := #[]
  range : Option SourceRange := none
  explicitStart : Bool := false
  explicitEnd : Bool := false
  deriving Repr, Inhabited

structure RepresentationStream where
  documents : Array RepresentationDocument := #[]
  leadingComments : Array Comment := #[]
  trailingComments : Array Comment := #[]
  deriving Repr, Inhabited

namespace Graph

private def propsOf : YamlNode → NodeProperties
  | .scalar _ _ props _ _ => props
  | .sequence _ _ props => props
  | .mapping _ _ props => props
  | .alias _ props => props

private def posOf (node : YamlNode) : SourcePos :=
  match (propsOf node).range with
  | some r => r.start
  | none => {}

private def err (node : YamlNode) (message : String) (kind : ComposeErrorKind) (path : Array String) : ComposeError :=
  { message, kind, position := posOf node, path }

private def contains (xs : Array String) (x : String) : Bool :=
  xs.any (· = x)

private def lookupAnchor? (anchors : Array (String × YamlNode)) (name : String) : Option YamlNode :=
  anchors.findSome? fun pair =>
    if pair.fst = name then some pair.snd else none

private def hasAnchor (anchors : Array (String × YamlNode)) (name : String) : Bool :=
  (lookupAnchor? anchors name).isSome

partial def collectAnchors (anchors : Array (String × YamlNode)) (node : YamlNode) (path : Array String := #[]) :
    Except ComposeError (Array (String × YamlNode)) := do
  let anchors ←
    match (propsOf node).anchor with
    | some name =>
        if hasAnchor anchors name then
          throw (err node s!"duplicate anchor &{name}" .duplicateAnchor path)
        else
          pure (anchors.push (name, node))
    | none => pure anchors
  match node with
  | .scalar .. | .alias .. => pure anchors
  | .sequence items _ _ =>
      let rec goSeq (idx : Nat) (items : List YamlNode) (acc : Array (String × YamlNode)) :
          Except ComposeError (Array (String × YamlNode)) := do
        match items with
        | [] => pure acc
        | item :: rest =>
            let acc ← collectAnchors acc item (path.push (toString idx))
            goSeq (idx + 1) rest acc
      goSeq 0 items.toList anchors
  | .mapping pairs _ _ =>
      let rec goMap (idx : Nat) (pairs : List (YamlNode × YamlNode)) (acc : Array (String × YamlNode)) :
          Except ComposeError (Array (String × YamlNode)) := do
        match pairs with
        | [] => pure acc
        | pair :: rest =>
            let acc ← collectAnchors acc pair.fst (path.push s!"<key:{idx}>")
            let acc ← collectAnchors acc pair.snd (path.push (toString idx))
            goMap (idx + 1) rest acc
      goMap 0 pairs.toList anchors

partial def expandNode (anchors : Array (String × YamlNode)) (stack : Array String) (path : Array String) :
    YamlNode → Except ComposeError YamlNode
  | .alias name props => do
      if contains stack name then
        throw (err (.alias name props) s!"recursive alias *{name}" .recursiveAlias path)
      match lookupAnchor? anchors name with
      | some target => expandNode anchors (stack.push name) path target
      | none => throw (err (.alias name props) s!"undefined alias *{name}" .undefinedAlias path)
  | .scalar value style props chomping indentHint =>
      pure (.scalar value style props chomping indentHint)
  | .sequence items style props => do
      let expanded ←
        items.foldlM (init := (#[] : Array YamlNode)) fun acc item => do
          let item ← expandNode anchors stack (path.push (toString acc.size)) item
          pure (acc.push item)
      pure (.sequence expanded style props)
  | .mapping pairs style props => do
      let expanded ←
        pairs.foldlM (init := (#[] : Array (YamlNode × YamlNode))) fun acc pair => do
          let key ← expandNode anchors stack (path.push s!"<key:{acc.size}>") pair.fst
          let value ← expandNode anchors stack (path.push (toString acc.size)) pair.snd
          pure (acc.push (key, value))
      pure (.mapping expanded style props)

def composeDocument (doc : YamlDocument) : Except ComposeError RepresentationDocument := do
  let anchors ← collectAnchors #[] doc.root
  let root ← expandNode anchors #[] #[] doc.root
  pure
    { directives := doc.directives
      root
      leadingComments := doc.leadingComments
      trailingComments := doc.trailingComments
      range := doc.range
      explicitStart := doc.explicitStart
      explicitEnd := doc.explicitEnd }

def composeStream (stream : YamlStream) : Except ComposeError RepresentationStream := do
  let documents ← stream.documents.mapM composeDocument
  pure { documents, leadingComments := stream.leadingComments, trailingComments := stream.trailingComments }

end Graph

def composeGraph (stream : YamlStream) : Except ComposeError RepresentationStream :=
  Graph.composeStream stream

def expandAliases (stream : YamlStream) : Except ComposeError RepresentationStream :=
  composeGraph stream

end Yaml
