import Yaml

open Yaml

def assertOk (name : String) (result : Except ParseError α) : IO α := do
  match result with
  | .ok value => pure value
  | .error err => throw (IO.userError s!"{name}: {err}")

def assertEqString (name expected actual : String) : IO Unit := do
  unless expected = actual do
    throw (IO.userError s!"{name}: expected {repr expected}, got {repr actual}")

def assertTrue (name : String) (condition : Bool) : IO Unit := do
  unless condition do
    throw (IO.userError s!"{name}: assertion failed")

def assertComposeError (name : String) (result : Except ComposeError α) : IO Unit := do
  match result with
  | .ok _ => throw (IO.userError s!"{name}: expected compose error")
  | .error _ => pure ()

def assertFromYamlError (name : String) (result : Except FromYamlError α) : IO Unit := do
  match result with
  | .ok _ => throw (IO.userError s!"{name}: expected FromYaml error")
  | .error _ => pure ()
