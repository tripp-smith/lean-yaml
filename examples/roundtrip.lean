import Yaml

open Yaml

def input : String :=
  "---\nname: lean-yaml\nports:\n  - 80\n  - 443\n"

def main : IO Unit := do
  match Yaml.parse input with
  | .ok stream => IO.println (Yaml.emit stream)
  | .error err => throw (IO.userError (toString err))
