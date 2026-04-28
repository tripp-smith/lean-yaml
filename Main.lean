import Yaml

open Yaml

def usage : String :=
  "usage: lean-yaml <parse|value|roundtrip|emit-value> <file>"

def readInputFile (path : String) : IO String :=
  IO.FS.readFile path

def printParseError (err : ParseError) : IO UInt32 := do
  IO.eprintln (toString err)
  return 1

def main (args : List String) : IO UInt32 := do
  match args with
  | ["parse", path] =>
      let input ← readInputFile path
      match Yaml.parse input with
      | .ok stream =>
          IO.println (repr stream)
          return 0
      | .error err => printParseError err
  | ["value", path] =>
      let input ← readInputFile path
      match Yaml.parseValue input with
      | .ok value =>
          IO.println (repr value)
          return 0
      | .error err => printParseError err
  | ["roundtrip", path] =>
      let input ← readInputFile path
      match Yaml.parse input with
      | .ok stream =>
          IO.println (Yaml.emit stream)
          return 0
      | .error err => printParseError err
  | ["emit-value", path] =>
      let input ← readInputFile path
      match Yaml.parseValue input with
      | .ok value =>
          IO.println (Yaml.emitValue value)
          return 0
      | .error err => printParseError err
  | _ =>
      IO.eprintln usage
      return 2
