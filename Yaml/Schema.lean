import Lean
import Yaml.AST
import Yaml.Error
import Yaml.Types

namespace Yaml

inductive Schema where
  | failsafe
  | json
  | core
  deriving Repr, Inhabited, DecidableEq

namespace Schema

private def lower (s : String) : String :=
  String.ofList (s.toList.map Char.toLower)

private def hasPrefix (p s : String) : Bool :=
  p.toList.isPrefixOf s.toList

private def dropChars (n : Nat) (s : String) : String :=
  String.ofList (s.toList.drop n)

private def allChars (p : Char → Bool) (s : String) : Bool :=
  s.toList.all p

private def isDigit (c : Char) : Bool :=
  c ≥ '0' && c ≤ '9'

private def isHexDigit (c : Char) : Bool :=
  isDigit c || (c ≥ 'a' && c ≤ 'f') || (c ≥ 'A' && c ≤ 'F')

private def stripSign (s : String) : String × Int :=
  if hasPrefix "-" s then (dropChars 1 s, -1)
  else if hasPrefix "+" s then (dropChars 1 s, 1)
  else (s, 1)

private def parseUnsignedBase? (base : Nat) (digit? : Char → Option Nat) (s : String) : Option Nat :=
  let rec go (acc : Nat) : List Char → Option Nat
    | [] => some acc
    | c :: cs =>
        match digit? c with
        | some d =>
            if d < base then go (acc * base + d) cs else none
        | none => none
  if s = "" then none else go 0 s.toList

private def decDigit? (c : Char) : Option Nat :=
  if isDigit c then some (c.toNat - '0'.toNat) else none

private def hexDigit? (c : Char) : Option Nat :=
  if c ≥ '0' && c <= '9' then some (c.toNat - '0'.toNat)
  else if c ≥ 'a' && c <= 'f' then some (10 + c.toNat - 'a'.toNat)
  else if c ≥ 'A' && c <= 'F' then some (10 + c.toNat - 'A'.toNat)
  else none

private def parseSignedDecimal? (s : String) (allowPlus : Bool) : Option Int :=
  if s = "" then none
  else if hasPrefix "+" s && !allowPlus then none
  else
    let (body, sign) := stripSign s
    if body = "" || !allChars isDigit body then none
    else
      match parseUnsignedBase? 10 decDigit? body with
      | some n => some (sign * n)
      | none => none

private def validJsonIntText (s : String) : Bool :=
  let body :=
    if hasPrefix "-" s then dropChars 1 s else s
  if body = "" then false
  else if body = "0" then true
  else !hasPrefix "0" body && allChars isDigit body

private def parseJsonInt? (s : String) : Option Int :=
  if validJsonIntText s then parseSignedDecimal? s false else none

private def parseCoreInt? (s : String) : Option Int :=
  let (body, sign) := stripSign s
  if body = "" then none
  else if hasPrefix "0x" body || hasPrefix "0X" body then
    match parseUnsignedBase? 16 hexDigit? (dropChars 2 body) with
    | some n => some (sign * n)
    | none => none
  else if hasPrefix "0o" body || hasPrefix "0O" body then
    match parseUnsignedBase? 8 decDigit? (dropChars 2 body) with
    | some n => some (sign * n)
    | none => none
  else
    parseSignedDecimal? s true

def isNullText (s : String) : Bool :=
  s = "" || s = "~" || lower s = "null"

def isBoolTrueText (s : String) : Bool :=
  lower s = "true"

def isBoolFalseText (s : String) : Bool :=
  lower s = "false"

private def isJsonNullText (s : String) : Bool :=
  s = "null"

private def isJsonBoolTrueText (s : String) : Bool :=
  s = "true"

private def isJsonBoolFalseText (s : String) : Bool :=
  s = "false"

private def parseJsonFloat? (s : String) : Option Float :=
  if s.contains '.' || s.contains 'e' || s.contains 'E' then
    match Lean.Json.parse s with
    | Except.ok j =>
        match j.getNum? with
        | .ok n => some n.toFloat
        | .error _ => none
    | Except.error _ => none
  else
    none

private def parseCoreFloat? (s : String) : Option Float :=
  parseJsonFloat? s

def resolvePlain (schema : Schema) (text : String) : YamlValue :=
  match schema with
  | .failsafe => .str text
  | .json =>
      if isJsonNullText text then
        .null
      else if isJsonBoolTrueText text then
        .bool true
      else if isJsonBoolFalseText text then
        .bool false
      else
        match parseJsonInt? text with
        | some i => .int i
        | none =>
            match parseJsonFloat? text with
            | some f => .float f
            | none => .str text
  | .core =>
      if isNullText text then
        .null
      else if isBoolTrueText text then
        .bool true
      else if isBoolFalseText text then
        .bool false
      else
        match parseCoreInt? text with
        | some i => .int i
        | none =>
            match parseCoreFloat? text with
            | some f => .float f
            | none => .str text

private def tagName (tag : String) : String :=
  match tag with
  | "!" => "!"
  | "!!str" => "tag:yaml.org,2002:str"
  | "!!seq" => "tag:yaml.org,2002:seq"
  | "!!map" => "tag:yaml.org,2002:map"
  | "!!bool" => "tag:yaml.org,2002:bool"
  | "!!int" => "tag:yaml.org,2002:int"
  | "!!float" => "tag:yaml.org,2002:float"
  | "!!null" => "tag:yaml.org,2002:null"
  | other => other

private def posOfProps (props : NodeProperties) : SourcePos :=
  match props.range with
  | some r => r.start
  | none => {}

private def schemaErr (message : String) (kind : SchemaErrorKind) (props : NodeProperties) (path : Array String) : SchemaError :=
  { message := message, kind := kind, position := posOfProps props, path := path }

private def resolveTaggedScalar (tag value : String) (props : NodeProperties) (path : Array String) : Except SchemaError YamlValue := do
  match tagName tag with
  | "!" => pure (.str value)
  | "tag:yaml.org,2002:str" => pure (.str value)
  | "tag:yaml.org,2002:null" =>
      if isNullText value then pure .null
      else throw (schemaErr s!"invalid null scalar {repr value}" .invalidScalar props path)
  | "tag:yaml.org,2002:bool" =>
      if isBoolTrueText value then pure (.bool true)
      else if isBoolFalseText value then pure (.bool false)
      else throw (schemaErr s!"invalid bool scalar {repr value}" .invalidScalar props path)
  | "tag:yaml.org,2002:int" =>
      match parseCoreInt? value with
      | some i => pure (.int i)
      | none => throw (schemaErr s!"invalid int scalar {repr value}" .invalidScalar props path)
  | "tag:yaml.org,2002:float" =>
      match parseCoreFloat? value with
      | some f => pure (.float f)
      | none => throw (schemaErr s!"invalid float scalar {repr value}" .invalidScalar props path)
  | other => pure (.custom other (.str value))

partial def resolveNode (schema : Schema) (node : YamlNode) (path : Array String := #[]) : Except SchemaError YamlValue := do
  match node with
  | .scalar value .plain props _ _ =>
      match props.tag with
      | some tag => resolveTaggedScalar tag value props path
      | none => pure (resolvePlain schema value)
  | .scalar value _ props _ _ =>
      match props.tag with
      | some tag => resolveTaggedScalar tag value props path
      | none => pure (.str value)
  | .sequence items _ props =>
      let values ← items.foldlM (init := (#[] : Array YamlValue)) fun acc item => do
        let idx := toString acc.size
        pure (acc.push (← resolveNode schema item (path.push idx)))
      match props.tag with
      | some tag =>
          match tagName tag with
          | "!" | "tag:yaml.org,2002:seq" => pure (.seq values)
          | other => pure (.custom other (.seq values))
      | none => pure (.seq values)
  | .mapping pairs _ props =>
      let values ← pairs.foldlM (init := (#[] : Array (YamlValue × YamlValue))) fun acc pair => do
        let key ← resolveNode schema pair.fst (path.push s!"<key:{acc.size}>")
        let value ← resolveNode schema pair.snd (path.push (toString acc.size))
        pure (acc.push (key, value))
      match props.tag with
      | some tag =>
          match tagName tag with
          | "!" | "tag:yaml.org,2002:map" => pure (.map values)
          | other => pure (.custom other (.map values))
      | none => pure (.map values)
  | .alias name props =>
      throw (schemaErr s!"unresolved alias *{name}" .invalidNode props path)

end Schema

def resolve (schema : Schema) (node : YamlNode) : Except SchemaError YamlValue :=
  Schema.resolveNode schema node

end Yaml
