namespace Yaml

structure SourcePos where
  line : Nat := 1
  column : Nat := 1
  offset : Nat := 0
  deriving Repr, Inhabited, DecidableEq

structure SourceRange where
  start : SourcePos := {}
  stop : SourcePos := {}
  deriving Repr, Inhabited, DecidableEq

inductive ScalarStyle where
  | plain
  | singleQuoted
  | doubleQuoted
  | literal
  | folded
  deriving Repr, Inhabited, DecidableEq

inductive CollectionStyle where
  | block
  | flow
  deriving Repr, Inhabited, DecidableEq

inductive Chomping where
  | strip
  | clip
  | keep
  deriving Repr, Inhabited, DecidableEq

inductive Directive where
  | yaml (version : String)
  | tag (handle : String) (uriPrefix : String)
  | reserved (name : String) (parameters : Array String)
  deriving Repr, Inhabited, DecidableEq

inductive CommentKind where
  | leading
  | trailing
  | inline
  | standalone
  deriving Repr, Inhabited, DecidableEq

structure Comment where
  text : String
  kind : CommentKind := .standalone
  range : SourceRange := {}
  indent : Nat := 0
  deriving Repr, Inhabited, DecidableEq

structure NodeTrivia where
  leading : Array Comment := #[]
  inline : Option Comment := none
  trailing : Array Comment := #[]
  detached : Array Comment := #[]
  deriving Repr, Inhabited, DecidableEq

structure NodeProperties where
  tag : Option String := none
  anchor : Option String := none
  trivia : NodeTrivia := {}
  range : Option SourceRange := none
  deriving Repr, Inhabited, DecidableEq

inductive YamlNode where
  | scalar
      (value : String)
      (style : ScalarStyle := .plain)
      (props : NodeProperties := {})
      (chomping : Option Chomping := none)
      (indentHint : Option Nat := none)
  | sequence
      (items : Array YamlNode)
      (style : CollectionStyle := .block)
      (props : NodeProperties := {})
  | mapping
      (pairs : Array (YamlNode × YamlNode))
      (style : CollectionStyle := .block)
      (props : NodeProperties := {})
  | alias (name : String) (props : NodeProperties := {})
  deriving Repr, Inhabited

structure YamlDocument where
  directives : Array Directive := #[]
  root : YamlNode := .scalar ""
  leadingComments : Array Comment := #[]
  trailingComments : Array Comment := #[]
  range : Option SourceRange := none
  explicitStart : Bool := false
  explicitEnd : Bool := false
  deriving Repr, Inhabited

structure YamlStream where
  documents : Array YamlDocument := #[]
  leadingComments : Array Comment := #[]
  trailingComments : Array Comment := #[]
  deriving Repr, Inhabited

end Yaml
