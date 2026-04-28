import Yaml.AST

namespace Yaml

inductive YamlEvent where
  | streamStart
  | streamEnd
  | documentStart (directives : Array Directive) (explicit : Bool)
  | documentEnd (explicit : Bool)
  | comment (comment : Comment)
  | scalar (value : String) (style : ScalarStyle) (props : NodeProperties) (chomping : Option Chomping) (indentHint : Option Nat)
  | sequenceStart (style : CollectionStyle) (props : NodeProperties)
  | sequenceEnd
  | mappingStart (style : CollectionStyle) (props : NodeProperties)
  | mappingEnd
  | alias (name : String) (props : NodeProperties)
  deriving Repr, Inhabited

namespace Event

private def propsText (props : NodeProperties) : String :=
  let tag :=
    match props.tag with
    | some tag => s!" tag={tag}"
    | none => ""
  let anchor :=
    match props.anchor with
    | some anchor => s!" anchor={anchor}"
    | none => ""
  tag ++ anchor

private def directiveText : Directive → String
  | .yaml version => s!"%YAML {version}"
  | .tag handle uriPrefix => s!"%TAG {handle} {uriPrefix}"
  | .reserved name parameters => "%" ++ name ++ (if parameters.isEmpty then "" else " " ++ String.intercalate " " parameters.toList)

private def styleText : ScalarStyle → String
  | .plain => "plain"
  | .singleQuoted => "single"
  | .doubleQuoted => "double"
  | .literal => "literal"
  | .folded => "folded"

private def collectionStyleText : CollectionStyle → String
  | .block => "block"
  | .flow => "flow"

private def chompingText : Chomping → String
  | .strip => "strip"
  | .clip => "clip"
  | .keep => "keep"

def renderEvent : YamlEvent → String
  | .streamStart => "+STR"
  | .streamEnd => "-STR"
  | .documentStart directives explicit =>
      let suffix :=
        if directives.isEmpty then ""
        else " " ++ String.intercalate " " (directives.toList.map directiveText)
      s!"+DOC explicit={explicit}{suffix}"
  | .documentEnd explicit => s!"-DOC explicit={explicit}"
  | .comment comment => s!"=COM indent={comment.indent} {repr comment.text}"
  | .scalar value style props chomping indentHint =>
      let chomping :=
        match chomping with
        | some c => s!" chomping={chompingText c}"
        | none => ""
      let indent :=
        match indentHint with
        | some n => s!" indent={n}"
        | none => ""
      s!"=VAL style={styleText style}{propsText props}{chomping}{indent} {repr value}"
  | .sequenceStart style props => s!"+SEQ style={collectionStyleText style}{propsText props}"
  | .sequenceEnd => "-SEQ"
  | .mappingStart style props => s!"+MAP style={collectionStyleText style}{propsText props}"
  | .mappingEnd => "-MAP"
  | .alias name props => s!"=ALI{propsText props} *{name}"

def renderEvents (events : Array YamlEvent) : String :=
  String.intercalate "\n" (events.toList.map renderEvent)

private def propComments (props : NodeProperties) : Array YamlEvent :=
  let detached := props.trivia.detached.map YamlEvent.comment
  let leading := props.trivia.leading.map YamlEvent.comment
  let inline :=
    match props.trivia.inline with
    | some c => #[YamlEvent.comment c]
    | none => #[]
  let trailing := props.trivia.trailing.map YamlEvent.comment
  detached ++ leading ++ inline ++ trailing

partial def ofNode : YamlNode → Array YamlEvent
  | .scalar value style props chomping indentHint =>
      propComments props ++ #[.scalar value style props chomping indentHint]
  | .alias name props =>
      propComments props ++ #[.alias name props]
  | .sequence items style props =>
      let children := items.foldl (init := #[]) fun acc item => acc ++ ofNode item
      propComments props ++ #[.sequenceStart style props] ++ children ++ #[.sequenceEnd]
  | .mapping pairs style props =>
      let children := pairs.foldl (init := #[]) fun acc pair => acc ++ ofNode pair.fst ++ ofNode pair.snd
      propComments props ++ #[.mappingStart style props] ++ children ++ #[.mappingEnd]

def ofDocument (doc : YamlDocument) : Array YamlEvent :=
  doc.leadingComments.map YamlEvent.comment ++
    #[.documentStart doc.directives doc.explicitStart] ++
    ofNode doc.root ++
    doc.trailingComments.map YamlEvent.comment ++
    #[.documentEnd doc.explicitEnd]

def ofStream (stream : YamlStream) : Array YamlEvent :=
  stream.leadingComments.map YamlEvent.comment ++
    #[.streamStart] ++
    stream.documents.foldl (init := #[]) (fun acc doc => acc ++ ofDocument doc) ++
    #[.streamEnd] ++
    stream.trailingComments.map YamlEvent.comment

end Event

def eventsOfStream (stream : YamlStream) : Array YamlEvent :=
  Event.ofStream stream

def eventsOfDocument (doc : YamlDocument) : Array YamlEvent :=
  Event.ofDocument doc

def emitEvents (events : Array YamlEvent) : String :=
  Event.renderEvents events

def emitStreamEvents (stream : YamlStream) : String :=
  emitEvents (eventsOfStream stream)

end Yaml
