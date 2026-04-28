import YamlTest.Support

open Yaml

def testSerde : IO Unit := do
  let xs : Array Nat ←
    match (fromYaml (.seq #[.int 1, .int 2]) : Except FromYamlError (Array Nat)) with
    | .ok xs => pure xs
    | .error err => throw (IO.userError s!"serde array: {err}")
  assertTrue "serde array size" (xs.size = 2)
  assertFromYamlError "serde path" ((fromYaml (.seq #[.int 1, .str "bad"]) : Except FromYamlError (Array Nat)))
  match (fromMapField #[(.str "name", .str "lean")] "name" : Except FromYamlError String) with
  | .ok "lean" => pure ()
  | other => throw (IO.userError s!"serde field helper: unexpected {repr other}")
  match (fromTagged "tag:example.com,2026:Name" (.custom "tag:example.com,2026:Name" (.str "lean")) : Except FromYamlError String) with
  | .ok "lean" => pure ()
  | other => throw (IO.userError s!"serde tag helper: unexpected {repr other}")

def testSerdeSuite : IO Unit := do
  testSerde
