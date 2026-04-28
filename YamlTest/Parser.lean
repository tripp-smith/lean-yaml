import YamlTest.Support

open Yaml

def testParserAndEmitter : IO Unit := do
  let stream ← assertOk "parse mapping" (Yaml.parse "name: lean\nports:\n  - 80\n  - 443\n")
  assertEqString "roundtrip" "name: lean\nports:\n  - 80\n  - 443" (Yaml.emit stream)
  let doc ← assertOk "parse document" (Yaml.parseDocument "---\nname: lean\n...\n")
  assertTrue "explicit start" doc.explicitStart
  assertTrue "explicit end" doc.explicitEnd
  let multi ← assertOk "multi-doc stream" (Yaml.parse "---\na: 1\n---\nb: 2\n")
  assertTrue "multi-doc count" (multi.documents.size = 2)
  let bytes := "\uFEFFname: lean\n".toUTF8
  let _ ← assertOk "parse byte array with BOM" (Yaml.parseByteArray bytes)
  pure ()

def testScalarsAndFlow : IO Unit := do
  let doc ← assertOk "literal scalar" (Yaml.parseDocument "text: |-\n  hello\n  world\n")
  match doc.root with
  | .mapping pairs _ _ =>
      match pairs[0]!.snd with
      | .scalar value .literal _ (some .strip) _ =>
          assertEqString "literal value" "hello\nworld" value
      | other => throw (IO.userError s!"literal scalar: unexpected node {repr other}")
  | other => throw (IO.userError s!"literal scalar: unexpected root {repr other}")
  let value ← assertOk "flow nested value" (Yaml.parseValue "items: [1, {enabled: true}, 'x,y']\n")
  match value with
  | .map pairs =>
      match pairs[0]!.snd with
      | .seq items => assertTrue "flow nested size" (items.size = 3)
      | other => throw (IO.userError s!"flow nested value: unexpected value {repr other}")
  | other => throw (IO.userError s!"flow nested value: unexpected root {repr other}")

def testRoundTripMetadata : IO Unit := do
  let input := "%YAML 1.2\n---\n# leading\nname: !e!thing value # inline\nblock: |+2\n    a\n    b\n"
  let doc ← assertOk "metadata parse" (Yaml.parseDocument input)
  match doc.directives[0]? with
  | some (Directive.yaml "1.2") => pure ()
  | other => throw (IO.userError s!"directive parse: unexpected {repr other}")
  let emitted := Yaml.emitDocument doc
  assertTrue "emits directive" (emitted.contains "%YAML 1.2")
  assertTrue "emits leading comment" (emitted.contains "# leading")
  assertTrue "emits inline comment" (emitted.contains "# inline")
  assertTrue "emits block scalar indicators" (emitted.contains "|+2")

def testTagHandlesAndComplexKeys : IO Unit := do
  let value ← assertOk "tag handle value" (Yaml.parseValue "%TAG !e! tag:example.com,2026:\n---\nitem: !e!widget yes\n")
  match value with
  | .map pairs =>
      match pairs[0]!.snd with
      | .custom "tag:example.com,2026:widget" (.str "yes") => pure ()
      | other => throw (IO.userError s!"tag handle value: unexpected {repr other}")
  | other => throw (IO.userError s!"tag handle value: unexpected root {repr other}")
  let complex ← assertOk "complex key" (Yaml.parseValue "? [a, b]\n: 1\n")
  match complex with
  | .map pairs =>
      match pairs[0]!.fst, pairs[0]!.snd with
      | .seq xs, .int 1 => assertTrue "complex key length" (xs.size = 2)
      | key, val => throw (IO.userError s!"complex key: unexpected {repr key} / {repr val}")
  | other => throw (IO.userError s!"complex key: unexpected root {repr other}")

def testParserSuite : IO Unit := do
  testParserAndEmitter
  testScalarsAndFlow
  testRoundTripMetadata
  testTagHandlesAndComplexKeys
