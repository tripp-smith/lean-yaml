namespace Yaml

inductive YamlValue where
  | null
  | bool (value : Bool)
  | int (value : Int)
  | float (value : Float)
  | str (value : String)
  | seq (items : Array YamlValue)
  | map (pairs : Array (YamlValue × YamlValue))
  | custom (tag : String) (value : YamlValue)
  deriving Repr, Inhabited

namespace YamlValue

private def hexDigit (n : Nat) : Char :=
  if n < 10 then
    Char.ofNat ('0'.toNat + n)
  else
    Char.ofNat ('A'.toNat + (n - 10))

private def jsonControlEscape (c : Char) : String :=
  let n := c.toNat
  "\\u00" ++ String.singleton (hexDigit (n / 16)) ++ String.singleton (hexDigit (n % 16))

private def escapeJsonString (s : String) : String :=
  let rec go (chars : List Char) (acc : String) : String :=
    match chars with
    | [] => acc
    | c :: rest =>
        let escaped :=
          match c with
          | '"' => "\\\""
          | '\\' => "\\\\"
          | '\n' => "\\n"
          | '\r' => "\\r"
          | '\t' => "\\t"
          | _ =>
              if c.toNat < 0x20 then jsonControlEscape c else String.singleton c
        go rest (acc ++ escaped)
  "\"" ++ go s.toList "" ++ "\""

partial def toJsonString? : YamlValue → Except String String
  | .null => pure "null"
  | .bool true => pure "true"
  | .bool false => pure "false"
  | .int value => pure (toString value)
  | .float value =>
      if value.isNaN || value.isInf then
        throw s!"JSON number must be finite, got {toString value}"
      else
        pure (toString value)
  | .str value => pure (escapeJsonString value)
  | .seq items => do
      let rendered ← items.mapM toJsonString?
      pure ("[" ++ String.intercalate "," rendered.toList ++ "]")
  | .map pairs => do
      let rendered ← pairs.mapM fun pair => do
        let key ←
          match pair.fst with
          | .str key => pure key
          | .custom _ (.str key) => pure key
          | other => throw s!"JSON object key must be a string, got {repr other}"
        let value ← toJsonString? pair.snd
        pure (escapeJsonString key ++ ":" ++ value)
      pure ("{" ++ String.intercalate "," rendered.toList ++ "}")
  | .custom _ value => toJsonString? value

end YamlValue

end Yaml
