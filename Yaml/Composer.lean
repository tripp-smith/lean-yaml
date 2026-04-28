import Yaml.AST
import Yaml.Error

namespace Yaml

namespace Composer

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
  { message := message, kind := kind, position := posOf node, path := path }

private def contains (xs : Array String) (x : String) : Bool :=
  xs.any (· = x)

private def collectAnchor (anchors : Array String) (node : YamlNode) (path : Array String) : Except ComposeError (Array String) := do
  match (propsOf node).anchor with
  | some name =>
      if contains anchors name then
        throw (err node s!"duplicate anchor &{name}" .duplicateAnchor path)
      else
        pure (anchors.push name)
  | none => pure anchors

partial def collectAnchors (anchors : Array String) (node : YamlNode) (path : Array String := #[]) : Except ComposeError (Array String) := do
  let anchors ← collectAnchor anchors node path
  match node with
  | .scalar .. | .alias .. => pure anchors
  | .sequence items _ _ =>
      items.foldlM (init := anchors) fun acc item =>
        collectAnchors acc item (path.push (toString acc.size))
  | .mapping pairs _ _ =>
      pairs.foldlM (init := anchors) fun acc pair => do
        let acc ← collectAnchors acc pair.fst (path.push "<key>")
        collectAnchors acc pair.snd (path.push (toString acc.size))

partial def validateAliases (anchors : Array String) (node : YamlNode) (path : Array String := #[]) : Except ComposeError Unit := do
  match node with
  | .alias name _ =>
      unless contains anchors name do
        throw (err node s!"undefined alias *{name}" .undefinedAlias path)
  | .scalar .. => pure ()
  | .sequence items _ _ =>
      let rec goSeq (idx : Nat) (items : List YamlNode) : Except ComposeError Unit := do
        match items with
        | [] => pure ()
        | item :: rest =>
            validateAliases anchors item (path.push (toString idx))
            goSeq (idx + 1) rest
      goSeq 0 items.toList
  | .mapping pairs _ _ =>
      let rec goMap (idx : Nat) (pairs : List (YamlNode × YamlNode)) : Except ComposeError Unit := do
        match pairs with
        | [] => pure ()
        | pair :: rest =>
            validateAliases anchors pair.fst (path.push s!"<key:{idx}>")
            validateAliases anchors pair.snd (path.push (toString idx))
            goMap (idx + 1) rest
      goMap 0 pairs.toList

def composeDocument (doc : YamlDocument) : Except ComposeError YamlDocument := do
  let anchors ← collectAnchors #[] doc.root
  validateAliases anchors doc.root
  pure doc

def composeStream (stream : YamlStream) : Except ComposeError YamlStream := do
  let documents ← stream.documents.mapM composeDocument
  pure { stream with documents := documents }

end Composer

def compose (stream : YamlStream) : Except ComposeError YamlStream :=
  Composer.composeStream stream

end Yaml
