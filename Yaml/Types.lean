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

end Yaml
