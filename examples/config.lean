import Yaml

open Yaml

def configYaml : String :=
  "name: lean-yaml\nfeatures:\n  - parser\n  - schema\n  - serde\n"

def main : IO Unit := do
  match Yaml.parseValue configYaml with
  | .ok value => IO.println (repr value)
  | .error err => throw (IO.userError (toString err))
