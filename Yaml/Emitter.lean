import Yaml.AST
import Yaml.Types

namespace Yaml

structure EmitOptions where
  indent : Nat := 2
  pretty : Bool := false
  explicitStart : Bool := false
  explicitEnd : Bool := false
  flow : Bool := false
  width : Nat := 80
  canonical : Bool := false
  deriving Repr, Inhabited

namespace Emitter

private def spaces (n : Nat) : String :=
  String.ofList (List.replicate n ' ')

private def quoteString (s : String) : String :=
  "\"" ++ ((s.replace "\\" "\\\\").replace "\"" "\\\"") ++ "\""

private def chompingText : Chomping → String
  | .strip => "-"
  | .clip => ""
  | .keep => "+"

private def scalarText (value : String) (style : ScalarStyle) (chomping : Option Chomping) (indentHint : Option Nat) : String :=
  match style with
  | .plain => value
  | .singleQuoted => "'" ++ value.replace "'" "''" ++ "'"
  | .doubleQuoted => quoteString value
  | .literal =>
      let hint := indentHint.map (fun n => toString n) |>.getD ""
      "|" ++ chompingText (chomping.getD .clip) ++ hint ++ "\n" ++ value
  | .folded =>
      let hint := indentHint.map (fun n => toString n) |>.getD ""
      ">" ++ chompingText (chomping.getD .clip) ++ hint ++ "\n" ++ value

private def propsText (props : NodeProperties) : String :=
  let tag :=
    match props.tag with
    | some t => t ++ " "
    | none => ""
  let anchor :=
    match props.anchor with
    | some a => "&" ++ a ++ " "
    | none => ""
  tag ++ anchor

private def directiveText : Directive → String
  | .yaml version => s!"%YAML {version}"
  | .tag handle uriPrefix => s!"%TAG {handle} {uriPrefix}"
  | .reserved name parameters => "%" ++ name ++ (if parameters.isEmpty then "" else " " ++ String.intercalate " " parameters.toList)

private def commentText (comment : Comment) : String :=
  spaces comment.indent ++ "# " ++ comment.text

private def leadingTrivia (props : NodeProperties) : String :=
  if props.trivia.leading.isEmpty && props.trivia.detached.isEmpty then
    ""
  else
    String.intercalate "\n" ((props.trivia.detached ++ props.trivia.leading).toList.map commentText) ++ "\n"

private def inlineTrivia (props : NodeProperties) : String :=
  match props.trivia.inline with
  | some c => " # " ++ c.text
  | none => ""

partial def emitNode (node : YamlNode) (level : Nat) (opts : EmitOptions) : String :=
  let pad := spaces level
  match node with
  | .scalar value style props chomping indentHint =>
      leadingTrivia props ++ propsText props ++ scalarText value style chomping indentHint ++ inlineTrivia props
  | .alias name props => leadingTrivia props ++ propsText props ++ "*" ++ name ++ inlineTrivia props
  | .sequence items .flow _ =>
      "[" ++ String.intercalate ", " (items.toList.map (fun item => emitNode item level opts)) ++ "]"
  | .sequence items .block _ =>
      String.intercalate "\n" <| items.toList.map fun item =>
        match item with
        | .scalar .. | .alias .. => pad ++ "- " ++ emitNode item (level + opts.indent) opts
        | _ => pad ++ "-\n" ++ emitNode item (level + opts.indent) opts
  | .mapping pairs .flow _ =>
      let parts := pairs.toList.map fun pair =>
        emitNode pair.fst level opts ++ ": " ++ emitNode pair.snd level opts
      "{" ++ String.intercalate ", " parts ++ "}"
  | .mapping pairs .block _ =>
      String.intercalate "\n" <| pairs.toList.map fun pair =>
        let key := emitNode pair.fst level opts
        match pair.snd with
        | .scalar .. | .alias .. =>
            pad ++ key ++ ": " ++ emitNode pair.snd (level + opts.indent) opts
        | _ =>
            pad ++ key ++ ":\n" ++ emitNode pair.snd (level + opts.indent) opts

def emitDocument (doc : YamlDocument) (opts : EmitOptions := {}) : String :=
  let directives :=
    if doc.directives.isEmpty then ""
    else String.intercalate "\n" (doc.directives.toList.map directiveText) ++ "\n"
  let leading :=
    if doc.leadingComments.isEmpty then ""
    else String.intercalate "\n" (doc.leadingComments.toList.map commentText) ++ "\n"
  let docPrefix := if opts.explicitStart || doc.explicitStart then "---\n" else ""
  let trailing :=
    if doc.trailingComments.isEmpty then ""
    else "\n" ++ String.intercalate "\n" (doc.trailingComments.toList.map commentText)
  let suffix := if opts.explicitEnd || doc.explicitEnd then "\n..." else ""
  directives ++ leading ++ docPrefix ++ emitNode doc.root 0 opts ++ trailing ++ suffix

def emitStream (stream : YamlStream) (opts : EmitOptions := {}) : String :=
  String.intercalate "\n" (stream.documents.toList.map (fun doc => emitDocument doc opts))

partial def valueToNode : YamlValue → YamlNode
  | .null => .scalar "null"
  | .bool true => .scalar "true"
  | .bool false => .scalar "false"
  | .int i => .scalar (toString i)
  | .float f => .scalar (toString f)
  | .str s => .scalar s .doubleQuoted
  | .seq xs => .sequence (xs.map valueToNode)
  | .map pairs => .mapping (pairs.map (fun pair => (valueToNode pair.fst, valueToNode pair.snd)))
  | .custom tag value =>
      let node := valueToNode value
      match node with
      | .scalar v style props ch indent => .scalar v style { props with tag := some tag } ch indent
      | .sequence xs style props => .sequence xs style { props with tag := some tag }
      | .mapping xs style props => .mapping xs style { props with tag := some tag }
      | .alias name props => .alias name { props with tag := some tag }

def emitValue (value : YamlValue) (opts : EmitOptions := {}) : String :=
  emitNode (valueToNode value) 0 opts

end Emitter

end Yaml
