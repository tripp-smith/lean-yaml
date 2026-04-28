import Yaml.Error
import Yaml.Types

namespace Yaml

class ToYaml (α : Type u) where
  toYaml : α → YamlValue

class FromYaml (α : Type u) where
  fromYaml : YamlValue → Except FromYamlError α

export ToYaml (toYaml)
export FromYaml (fromYaml)

instance : ToYaml String where
  toYaml := YamlValue.str

instance : FromYaml String where
  fromYaml
    | .str s => .ok s
    | other => .error { message := s!"expected YAML string, got {repr other}" }

instance : ToYaml Bool where
  toYaml := YamlValue.bool

instance : FromYaml Bool where
  fromYaml
    | .bool b => .ok b
    | other => .error { message := s!"expected YAML bool, got {repr other}" }

instance : ToYaml Int where
  toYaml := YamlValue.int

instance : FromYaml Int where
  fromYaml
    | .int i => .ok i
    | other => .error { message := s!"expected YAML int, got {repr other}" }

instance : ToYaml Nat where
  toYaml n := YamlValue.int n

instance : FromYaml Nat where
  fromYaml
    | .int i =>
        if i >= 0 then
          .ok i.toNat
        else
          .error { message := s!"expected non-negative YAML int, got {i}" }
    | other => .error { message := s!"expected YAML nat, got {repr other}" }

instance : ToYaml Float where
  toYaml := YamlValue.float

instance : FromYaml Float where
  fromYaml
    | .float f => .ok f
    | .int i => .ok (Float.ofInt i)
    | other => .error { message := s!"expected YAML float, got {repr other}" }

instance : ToYaml Unit where
  toYaml _ := .null

instance : FromYaml Unit where
  fromYaml
    | .null => .ok ()
    | other => .error { message := s!"expected YAML null, got {repr other}" }

instance [ToYaml α] : ToYaml (Array α) where
  toYaml xs := .seq (xs.map toYaml)

instance [FromYaml α] : FromYaml (Array α) where
  fromYaml
    | .seq xs =>
        xs.foldlM (init := #[]) fun acc value => do
          match fromYaml value with
          | .ok parsed => pure (acc.push parsed)
          | .error err => throw (FromYamlError.prependPath (toString acc.size) err)
    | other => .error { message := s!"expected YAML sequence, got {repr other}" }

instance [ToYaml α] : ToYaml (List α) where
  toYaml xs := .seq (xs.toArray.map toYaml)

instance [FromYaml α] : FromYaml (List α) where
  fromYaml value := do
    let xs : Array α ← fromYaml value
    pure xs.toList

instance [ToYaml α] : ToYaml (Option α) where
  toYaml
    | none => .null
    | some value => toYaml value

instance [FromYaml α] : FromYaml (Option α) where
  fromYaml
    | .null => .ok none
    | value => some <$> fromYaml value

def lookupKey? (key : String) (pairs : Array (YamlValue × YamlValue)) : Option YamlValue :=
  pairs.findSome? fun pair =>
    match pair.fst with
    | .str k => if k = key then some pair.snd else none
    | _ => none

def fromMapField [FromYaml α] (pairs : Array (YamlValue × YamlValue)) (key : String) : Except FromYamlError α := do
  match lookupKey? key pairs with
  | some value =>
      match fromYaml value with
      | .ok parsed => pure parsed
      | .error err => throw (FromYamlError.prependPath key err)
  | none => throw { message := s!"missing required field {key}", path := #[key] }

def fromTagged [FromYaml α] (expectedTag : String) : YamlValue → Except FromYamlError α
  | .custom tag value =>
      if tag = expectedTag then
        fromYaml value
      else
        .error { message := s!"expected tag {expectedTag}, got {tag}" }
  | other => .error { message := s!"expected tagged YAML value {expectedTag}, got {repr other}" }

def withTag (tag : String) (value : YamlValue) : YamlValue :=
  .custom tag value

end Yaml
