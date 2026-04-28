import YamlTest.Support

open Yaml

def testStreamingApis : IO Unit := do
  IO.FS.createDirAll (System.mkFilePath ["build"])
  let path := System.mkFilePath ["build", "yaml-stream-test.yaml"]
  let out := System.mkFilePath ["build", "yaml-stream-out.yaml"]
  IO.FS.writeFile path "---\na: 1\n---\nb: 2\n"
  let seen ← IO.mkRef 0
  match (← Yaml.parseStreamFromFile path fun _ => seen.modify (· + 1)) with
  | .ok () => pure ()
  | .error err => throw (IO.userError s!"stream parse: {err}")
  assertTrue "stream parse document count" ((← seen.get) = 2)
  let stream ← assertOk "stream parse for emit" (Yaml.parse "---\na: 1\n---\nb: 2\n")
  Yaml.emitStreamToFile out stream
  let emitted ← IO.FS.readFile out
  assertTrue "stream emit output" (emitted.contains "a: 1" && emitted.contains "b: 2")

def testEventApis : IO Unit := do
  let stream ← assertOk "events parse" (Yaml.parse "---\na: 1\n")
  let events := Yaml.eventsOfStream stream
  assertTrue "events include stream start" (events.any (fun e => match e with | .streamStart => true | _ => false))
  assertTrue "events include mapping start" (events.any (fun e => match e with | .mappingStart .. => true | _ => false))
  assertTrue "events include scalar" (events.any (fun e => match e with | .scalar "a" .. => true | _ => false))
  let rendered := Yaml.emitEvents events
  assertTrue "rendered events include stream" (rendered.contains "+STR")
  assertTrue "rendered events include scalar" (rendered.contains "=VAL")

def testStreamingSuite : IO Unit := do
  testStreamingApis
  testEventApis
