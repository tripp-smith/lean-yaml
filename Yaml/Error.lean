import Yaml.AST

namespace Yaml

inductive ParseErrorKind where
  | unexpectedEnd
  | unexpectedToken
  | invalidIndentation
  | invalidDirective
  | invalidEncoding
  | unsupportedFeature
  | invalidScalar
  deriving Repr, Inhabited, DecidableEq

structure ParseError where
  message : String
  kind : ParseErrorKind := .unexpectedToken
  position : SourcePos := {}
  context : Array String := #[]
  deriving Repr, Inhabited, DecidableEq

instance : ToString ParseError where
  toString err :=
    s!"{err.position.line}:{err.position.column}: {err.message}"

inductive ComposeErrorKind where
  | duplicateAnchor
  | undefinedAlias
  | recursiveAlias
  | invalidDocument
  deriving Repr, Inhabited, DecidableEq

structure ComposeError where
  message : String
  kind : ComposeErrorKind := .invalidDocument
  position : SourcePos := {}
  path : Array String := #[]
  deriving Repr, Inhabited, DecidableEq

instance : ToString ComposeError where
  toString err :=
    s!"{err.position.line}:{err.position.column}: {err.message}"

inductive SchemaErrorKind where
  | unsupportedTag
  | invalidScalar
  | invalidNode
  deriving Repr, Inhabited, DecidableEq

structure SchemaError where
  message : String
  kind : SchemaErrorKind := .invalidNode
  position : SourcePos := {}
  path : Array String := #[]
  deriving Repr, Inhabited, DecidableEq

instance : ToString SchemaError where
  toString err :=
    s!"{err.position.line}:{err.position.column}: {err.message}"

structure FromYamlError where
  message : String
  path : Array String := #[]
  deriving Repr, Inhabited, DecidableEq

namespace FromYamlError

def prependPath (segment : String) (err : FromYamlError) : FromYamlError :=
  { err with path := #[segment] ++ err.path }

end FromYamlError

instance : ToString FromYamlError where
  toString err :=
    let path :=
      if err.path.isEmpty then "$"
      else "$." ++ String.intercalate "." err.path.toList
    s!"{path}: {err.message}"

end Yaml
