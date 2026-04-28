import Yaml

open Yaml

structure Service where
  name : String
  enabled : Bool
  ports : Array Nat
  deriving Repr

def serviceToYaml (service : Service) : YamlValue :=
  .map #[
    (.str "name", toYaml service.name),
    (.str "enabled", toYaml service.enabled),
    (.str "ports", toYaml service.ports)
  ]

def main : IO Unit := do
  let service : Service := { name := "api", enabled := true, ports := #[80, 443] }
  IO.println (Yaml.emitValue (serviceToYaml service))
