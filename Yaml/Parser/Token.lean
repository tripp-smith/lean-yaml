import Yaml.AST
import Yaml.Parser.Source

namespace Yaml
namespace Parser

inductive YamlContext where
  | blockIn
  | blockOut
  | flowIn
  | flowOut
  | blockKey
  | flowKey
  deriving Repr, Inhabited, DecidableEq

inductive TokenKind where
  | streamStart
  | streamEnd
  | documentStart
  | documentEnd
  | directive
  | comment
  | scalar
  | alias
  | anchor
  | tag
  | blockSequenceEntry
  | mappingKey
  | mappingValue
  | flowSequenceStart
  | flowSequenceEnd
  | flowMappingStart
  | flowMappingEnd
  | flowEntry
  | indentation
  | lineBreak
  deriving Repr, Inhabited, DecidableEq

structure Token where
  kind : TokenKind
  text : String := ""
  range : SourceRange := {}
  context : Option YamlContext := none
  deriving Repr, Inhabited, DecidableEq

structure TokenStream where
  tokens : Array Token := #[]
  source : SourceBuffer := { input := "" }
  deriving Repr, Inhabited

end Parser
end Yaml
