import YamlTest.Support

open Yaml

def testSchemaAndCompose : IO Unit := do
  let core ← assertOk "core bool" (Yaml.parseValue "flag: TRUE\n")
  let json ← assertOk "json bool strictness" (Yaml.parseValue "flag: TRUE\n" Schema.json)
  match core, json with
  | .map corePairs, .map jsonPairs =>
      match corePairs[0]!.snd, jsonPairs[0]!.snd with
      | .bool true, .str "TRUE" => pure ()
      | a, b => throw (IO.userError s!"schema strictness: unexpected {repr a} / {repr b}")
  | _, _ => throw (IO.userError "schema strictness: expected maps")
  let anchored ← assertOk "anchor parse" (Yaml.parse "left: &base 1\nright: *base\n")
  match Yaml.compose anchored with
  | .ok _ => pure ()
  | .error err => throw (IO.userError s!"anchor compose: {err}")
  let missing ← assertOk "missing alias parse" (Yaml.parse "right: *missing\n")
  assertComposeError "missing alias compose" (Yaml.compose missing)

def testSchemaNumbers : IO Unit := do
  let jsonLeadingZero ← assertOk "json leading zero" (Yaml.parseValue "n: 01\n" Schema.json)
  let coreHex ← assertOk "core hex" (Yaml.parseValue "n: 0x10\n" Schema.core)
  let coreOctal ← assertOk "core octal" (Yaml.parseValue "n: 0o10\n" Schema.core)
  let jsonFloat ← assertOk "json float" (Yaml.parseValue "n: 1.5e2\n" Schema.json)
  match jsonLeadingZero, coreHex, coreOctal, jsonFloat with
  | .map a, .map b, .map c, .map d =>
      match a[0]!.snd, b[0]!.snd, c[0]!.snd, d[0]!.snd with
      | .str "01", .int 16, .int 8, .float _ => pure ()
      | w, x, y, z => throw (IO.userError s!"schema numbers: unexpected {repr w} / {repr x} / {repr y} / {repr z}")
  | _, _, _, _ => throw (IO.userError "schema numbers: expected maps")

def testRepresentationGraph : IO Unit := do
  let stream ← assertOk "graph parse" (Yaml.parse "base: &base 1\ncopy: *base\n")
  let graph ←
    match Yaml.composeGraph stream with
    | .ok graph => pure graph
    | .error err => throw (IO.userError s!"compose graph: {err}")
  match graph.documents[0]!.root with
  | .mapping pairs _ _ =>
      match pairs[1]!.snd with
      | .scalar "1" .plain _ _ _ => pure ()
      | other => throw (IO.userError s!"expanded alias scalar: unexpected {repr other}")
  | other => throw (IO.userError s!"compose graph root: unexpected {repr other}")
  let recursive ← assertOk "recursive alias parse" (Yaml.parse "self: &self *self\n")
  assertComposeError "recursive alias graph" (Yaml.composeGraph recursive)

def testComposerSuite : IO Unit := do
  testSchemaAndCompose
  testSchemaNumbers
  testRepresentationGraph
