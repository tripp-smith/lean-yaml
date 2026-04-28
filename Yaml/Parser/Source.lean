import Yaml.AST
import Yaml.Error

namespace Yaml
namespace Parser

structure SourceSlice where
  source : String
  start : Nat := 0
  stop : Nat := 0
  range : SourceRange := {}
  deriving Repr, Inhabited, DecidableEq

namespace SourceSlice

private def takeChars (n : Nat) (s : String) : String :=
  String.ofList (s.toList.take n)

private def dropChars (n : Nat) (s : String) : String :=
  String.ofList (s.toList.drop n)

def toString (slice : SourceSlice) : String :=
  takeChars (slice.stop - slice.start) (dropChars slice.start slice.source)

end SourceSlice

structure SourceBuffer where
  input : String
  deriving Repr, Inhabited

namespace SourceBuffer

def ofString (input : String) : SourceBuffer :=
  { input }

def toSlice (source : SourceBuffer) (start stop : Nat) (range : SourceRange := {}) : SourceSlice :=
  { source := source.input, start, stop, range }

end SourceBuffer

end Parser
end Yaml
