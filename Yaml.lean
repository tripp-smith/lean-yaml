import Yaml.AST
import Yaml.Composer
import Yaml.Emitter
import Yaml.Error
import Yaml.Event
import Yaml.Graph
import Yaml.Parser
import Yaml.Parser.Source
import Yaml.Parser.Token
import Yaml.Schema
import Yaml.Serde
import Yaml.Types

namespace Yaml

def parse (input : String) : Except ParseError YamlStream :=
  Parser.parse input

def parseValue (input : String) (schema : Schema := Schema.core) : Except ParseError YamlValue :=
  Parser.parseValue input schema

def parseDocument (input : String) : Except ParseError YamlDocument :=
  Parser.parseDocument input

def parseByteArray (input : ByteArray) : Except ParseError YamlStream :=
  Parser.parseByteArray input

def emit (stream : YamlStream) (opts : EmitOptions := {}) : String :=
  Emitter.emitStream stream opts

def emitValue (value : YamlValue) (opts : EmitOptions := {}) : String :=
  Emitter.emitValue value opts

def emitDocument (doc : YamlDocument) (opts : EmitOptions := {}) : String :=
  Emitter.emitDocument doc opts

def parseStream (input : String) : IO (Except ParseError YamlStream) :=
  pure (parse input)

def emitStream (stream : YamlStream) (opts : EmitOptions := {}) : IO String :=
  pure (emit stream opts)

def parseStreamFromFile (path : System.FilePath) (onDocument : YamlDocument → IO Unit) : IO (Except ParseError Unit) := do
  let input ← IO.FS.readFile path
  match parse input with
  | .error err => pure (.error err)
  | .ok stream =>
      for doc in stream.documents do
        onDocument doc
      pure (.ok ())

def emitStreamToFile (path : System.FilePath) (stream : YamlStream) (opts : EmitOptions := {}) : IO Unit := do
  let h ← IO.FS.Handle.mk path IO.FS.Mode.write
  for i in [0:stream.documents.size] do
    if i > 0 then
      h.putStr "\n"
    h.putStr (emitDocument stream.documents[i]! opts)
  h.flush

end Yaml
