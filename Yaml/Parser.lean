import Parser
import Yaml.AST
import Yaml.Composer
import Yaml.Error
import Yaml.Schema
import Yaml.Types

namespace Yaml
namespace Parser

structure Line where
  number : Nat
  raw : String
  indent : Nat
  content : String
  deriving Repr, Inhabited

private def isSpace (c : Char) : Bool :=
  c = ' ' || c = '\t' || c = '\n' || c = '\r'

private def ltrimList : List Char → List Char
  | [] => []
  | c :: cs => if isSpace c then ltrimList cs else c :: cs

private def rtrimList (chars : List Char) : List Char :=
  chars.reverse |> ltrimList |> List.reverse

private def trim (s : String) : String :=
  String.ofList (rtrimList (ltrimList s.toList))

private def hasPrefix (p s : String) : Bool :=
  p.toList.isPrefixOf s.toList

private def hasSuffix (p s : String) : Bool :=
  p.toList.reverse.isPrefixOf s.toList.reverse

private def dropChars (n : Nat) (s : String) : String :=
  String.ofList (s.toList.drop n)

private def dropLastChar (s : String) : String :=
  String.ofList ((s.toList.reverse.drop 1).reverse)

private def takeChars (n : Nat) (s : String) : String :=
  String.ofList (s.toList.take n)

private def byteAt? (bytes : ByteArray) (i : Nat) : Option UInt8 :=
  if h : i < bytes.size then some bytes[i] else none

private def countIndent (s : String) : Nat :=
  let rec go : List Char → Nat
    | [] => 0
    | c :: cs => if c = ' ' then go cs + 1 else 0
  go s.toList

private def splitComment (s : String) : String × Option String :=
  let rec go (acc : List Char) (quote : Option Char) : List Char → String × Option String
    | [] => (String.ofList acc.reverse, none)
    | c :: rest =>
        match quote, c with
        | none, '\'' => go (c :: acc) (some '\'') rest
        | none, '"' => go (c :: acc) (some '"') rest
        | none, '#' => (String.ofList acc.reverse, some (String.ofList rest))
        | some q, c =>
            if c = q then go (c :: acc) none rest else go (c :: acc) quote rest
        | none, _ => go (c :: acc) none rest
  go [] none s.toList

private def mkLine (n : Nat) (raw : String) : Line :=
  let indent := countIndent raw
  { number := n, raw := raw, indent := indent, content := trim (dropChars indent raw) }

private def makeComment (line : Line) (text : String) (kind : CommentKind) : Comment :=
  { text := trim text
    kind := kind
    range := { start := { line := line.number, column := line.indent + 1 }, stop := { line := line.number, column := line.raw.length + 1 } }
    indent := line.indent }

private def err (line : Line) (message : String) (kind : ParseErrorKind := .unexpectedToken) : ParseError :=
  { message := message, kind := kind, position := { line := line.number, column := line.indent + 1 } }

private def scalarStyleOf (s : String) : ScalarStyle :=
  if hasPrefix "'" s then .singleQuoted
  else if hasPrefix "\"" s then .doubleQuoted
  else .plain

private def unquote (s : String) : String :=
  let chars := s.toList
  match chars with
  | '\'' :: rest =>
      match rest.reverse with
      | '\'' :: body => (String.ofList body.reverse).replace "''" "'"
      | _ => s
  | '"' :: rest =>
      match rest.reverse with
      | '"' :: body =>
          let raw := String.ofList body.reverse
          ((((((raw.replace "\\n" "\n").replace "\\t" "\t").replace "\\r" "\r").replace "\\\"" "\"").replace "\\\\" "\\").replace "\\/" "/")
      | _ => s
  | _ => s

private def expandTag (directives : Array Directive) (tag : String) : String :=
  if hasPrefix "!!" tag then
    "tag:yaml.org,2002:" ++ dropChars 2 tag
  else if hasPrefix "!" tag && tag.length > 1 then
    let rec go (dirs : List Directive) : String :=
      match dirs with
      | [] => tag
      | .tag handle uriPrefix :: rest =>
          if handle ≠ "!" && hasPrefix handle tag then
            uriPrefix ++ dropChars handle.length tag
          else
            go rest
      | _ :: rest => go rest
    go directives.toList
  else
    tag

private def parseProps (directives : Array Directive) (text : String) : NodeProperties × String :=
  let rec go (props : NodeProperties) (parts : List String) : NodeProperties × String :=
    match parts with
    | [] => (props, "")
    | part :: rest =>
        if hasPrefix "&" part && part.length > 1 then
          go { props with anchor := some (dropChars 1 part) } rest
        else if hasPrefix "!" part && part.length > 1 then
          go { props with tag := some (expandTag directives part) } rest
        else
          (props, String.intercalate " " (part :: rest))
  go {} (text.splitOn " " |>.filter (· ≠ ""))

private def scalarNode (directives : Array Directive) (text : String) : YamlNode :=
  let body := trim text
  let (props, body) := parseProps directives body
  if hasPrefix "*" body then
    .alias (dropChars 1 body) props
  else
    .scalar (unquote body) (scalarStyleOf body) props

private def isFlowOpen : Char → Bool
  | '[' | '{' => true
  | _ => false

private def isFlowClose : Char → Bool
  | ']' | '}' => true
  | _ => false

private def splitTopLevel (sep : Char) (s : String) : List String :=
  let rec go (acc : List Char) (out : List String) (depth : Nat) (quote : Option Char) : List Char → List String
    | [] => (String.ofList acc.reverse) :: out |>.reverse
    | c :: rest =>
        match quote with
        | some q =>
            if c = q then go (c :: acc) out depth none rest
            else go (c :: acc) out depth quote rest
        | none =>
            if c = '\'' then go (c :: acc) out depth (some '\'') rest
            else if c = '"' then go (c :: acc) out depth (some '"') rest
            else if isFlowOpen c then go (c :: acc) out (depth + 1) none rest
            else if isFlowClose c then go (c :: acc) out (depth - 1) none rest
            else if c = sep && depth = 0 then
              go [] ((String.ofList acc.reverse) :: out) depth none rest
            else
              go (c :: acc) out depth none rest
  go [] [] 0 none s.toList

private def splitKeyValue (s : String) : Option (String × String) :=
  let rec go (acc : List Char) (depth : Nat) (quote : Option Char) : List Char → Option (String × String)
    | [] => none
    | c :: rest =>
        match quote with
        | some q =>
            if c = q then go (c :: acc) depth none rest
            else go (c :: acc) depth quote rest
        | none =>
            if c = '\'' then go (c :: acc) depth (some '\'') rest
            else if c = '"' then go (c :: acc) depth (some '"') rest
            else if isFlowOpen c then go (c :: acc) (depth + 1) none rest
            else if isFlowClose c then go (c :: acc) (depth - 1) none rest
            else if c = ':' && depth = 0 then
              some (String.ofList acc.reverse, String.ofList rest)
            else
              go (c :: acc) depth none rest
  go [] 0 none s.toList

mutual

partial def parseFlowSeq (directives : Array Directive) (s : String) : YamlNode :=
  let inner := dropChars 1 s
  let inner := dropLastChar inner
  let items := splitTopLevel ',' inner |>.filterMap (fun item =>
    let item := trim item
    if item = "" then none else some (parseScalarLike directives item)) |> List.toArray
  .sequence items .flow

partial def parseFlowMap (directives : Array Directive) (s : String) : YamlNode :=
  let inner := dropChars 1 s
  let inner := dropLastChar inner
  let pairs := splitTopLevel ',' inner |>.filterMap fun item =>
    match splitKeyValue item with
    | some (key, value) => some (scalarNode directives (trim key), parseScalarLike directives (trim value))
    | none => none
  .mapping pairs.toArray .flow

partial def parseScalarLike (directives : Array Directive) (s : String) : YamlNode :=
  let body := trim s
  if hasPrefix "[" body && hasSuffix "]" body then parseFlowSeq directives body
  else if hasPrefix "{" body && hasSuffix "}" body then parseFlowMap directives body
  else scalarNode directives body

end

private def parseBlockScalarHeader (s : String) : Option (ScalarStyle × Chomping × Option Nat) :=
  let body := trim s
  if body = "" then none
  else
    let style? :=
      if hasPrefix "|" body then some ScalarStyle.literal
      else if hasPrefix ">" body then some ScalarStyle.folded
      else none
    match style? with
    | none => none
    | some style =>
        let indicators := (dropChars 1 body).toList
        let chomping :=
          if indicators.contains '-' then .strip
          else if indicators.contains '+' then .keep
          else .clip
        let indentHint :=
          indicators.find? (fun c => c ≥ '1' && c ≤ '9') |>.map (fun c => c.toNat - '0'.toNat)
        some (style, chomping, indentHint)

private def applyChomping (chomping : Chomping) (s : String) : String :=
  let stripTrailingNewlines (s : String) : String :=
    String.ofList ((s.toList.reverse.dropWhile (· = '\n')).reverse)
  match chomping with
  | .strip => stripTrailingNewlines s
  | .clip =>
      let stripped := stripTrailingNewlines s
      stripped ++ "\n"
  | .keep => s

private def foldLines (s : String) : String :=
  String.intercalate " " (s.splitOn "\n")

private def parseBlockScalar (lines : Array Line) (start : Nat) (parentIndent : Nat) (style : ScalarStyle) (chomping : Chomping) (indentHint : Option Nat) : YamlNode × Nat :=
  Id.run do
    let mut i := start
    let mut bodyLines : Array String := #[]
    let contentIndent :=
      match indentHint with
      | some hint => parentIndent + hint
      | none =>
          match lines[start]? with
          | some first => if first.indent > parentIndent then first.indent else parentIndent + 1
          | none => parentIndent + 1
    while h : i < lines.size do
      let line := lines[i]
      if line.indent < contentIndent then
        break
      bodyLines := bodyLines.push (dropChars (min contentIndent line.raw.length) line.raw)
      i := i + 1
    let raw := String.intercalate "\n" bodyLines.toList
    let body := if style = .folded then foldLines raw else raw
    (.scalar (applyChomping chomping body) style {} (some chomping) indentHint, i)

mutual

partial def parseBlock (directives : Array Directive) (lines : Array Line) (start : Nat) (indent : Nat) : Except ParseError (YamlNode × Nat) := do
  if h : start < lines.size then
    let line := lines[start]
    if line.indent < indent then
      throw (err line "invalid block start" .invalidIndentation)
    else if line.raw.toList.take line.indent |>.contains '\t' then
      throw (err line "tabs are not allowed for indentation" .invalidIndentation)
    else if hasPrefix "- " line.content || line.content = "-" then
      parseSeq directives lines start line.indent
    else if line.content.contains ':' || hasPrefix "? " line.content || line.content = "?" then
      parseMap directives lines start line.indent
    else
      let (body, inline) := splitComment line.content
      match parseBlockScalarHeader body with
      | some (style, chomping, indentHint) =>
          return parseBlockScalar lines (start + 1) line.indent style chomping indentHint
      | none =>
          let props :=
            match inline with
            | some c => { ({} : NodeProperties) with trivia := { inline := some (makeComment line c .inline) } }
            | none => {}
          return (.scalar (unquote (trim body)) (scalarStyleOf (trim body)) props, start + 1)
  else
    throw { message := "unexpected end of input", kind := .unexpectedEnd }

partial def parseSeq (directives : Array Directive) (lines : Array Line) (start : Nat) (indent : Nat) : Except ParseError (YamlNode × Nat) := do
  let mut i := start
  let mut items : Array YamlNode := #[]
  while h : i < lines.size do
    let line := lines[i]
    if line.indent ≠ indent || !(hasPrefix "- " line.content || line.content = "-") then
      break
    let rest := trim (if line.content = "-" then "" else dropChars 2 line.content)
    if rest = "" then
      let parsed ← parseBlock directives lines (i + 1) (indent + 1)
      items := items.push parsed.fst
      i := parsed.snd
    else
      match parseBlockScalarHeader rest with
      | some (style, chomping, indentHint) =>
          let (node, next) := parseBlockScalar lines (i + 1) line.indent style chomping indentHint
          items := items.push node
          i := next
      | none =>
          items := items.push (parseScalarLike directives rest)
          i := i + 1
  return (.sequence items .block, i)

partial def parseMap (directives : Array Directive) (lines : Array Line) (start : Nat) (indent : Nat) : Except ParseError (YamlNode × Nat) := do
  let mut i := start
  let mut pairs : Array (YamlNode × YamlNode) := #[]
  while h : i < lines.size do
    let line := lines[i]
    if line.indent ≠ indent || (!(line.content.contains ':') && !(hasPrefix "? " line.content || line.content = "?")) || hasPrefix "- " line.content then
      break
    let (withoutComment, inlineComment) := splitComment line.content
    let explicitKey := hasPrefix "? " withoutComment || trim withoutComment = "?"
    let keyAndRest? : Option (YamlNode × String) :=
      if explicitKey then
        let keyText := trim (if trim withoutComment = "?" then "" else dropChars 1 withoutComment)
        if keyText = "" then
          none
        else
          some (parseScalarLike directives keyText, "")
      else
        match splitKeyValue withoutComment with
        | some (key, rest) => some (scalarNode directives (trim key), rest)
        | none => none
    match keyAndRest? with
    | some (key, rest) =>
        let keyNode := key
        let valueText ←
          if explicitKey then
            match lines[i + 1]? with
            | some nextLine =>
                let (nextNoComment, _) := splitComment nextLine.content
                if nextLine.indent = indent && hasPrefix ":" (trim nextNoComment) then
                  i := i + 1
                  pure (trim (dropChars 1 (trim nextNoComment)))
                else
                  pure ""
            | none => pure ""
          else
            pure (trim rest)
        let valueNode ←
          if valueText = "" then
            let parsed ← parseBlock directives lines (i + 1) (indent + 1)
            i := parsed.snd
            pure parsed.fst
          else
            match parseBlockScalarHeader valueText with
            | some (style, chomping, indentHint) =>
                let (node, next) := parseBlockScalar lines (i + 1) line.indent style chomping indentHint
                i := next
                pure node
            | none =>
                i := i + 1
                pure (parseScalarLike directives valueText)
        let valueNode :=
          match inlineComment, valueNode with
          | some c, .scalar value style props ch hint =>
              .scalar value style { props with trivia := { props.trivia with inline := some (makeComment line c .inline) } } ch hint
          | _, node => node
        pairs := pairs.push (keyNode, valueNode)
    | none => throw (err line "expected mapping key")
  return (.mapping pairs .block, i)

end

private def preprocessLines (rawLines : List (Nat × String)) : Array Line × Array Comment × Array Directive :=
  Id.run do
    let mut lines : Array Line := #[]
    let mut comments : Array Comment := #[]
    let mut directives : Array Directive := #[]
    for (n, raw) in rawLines do
      let line := mkLine n raw
      if line.content = "" then
        pure ()
      else if hasPrefix "#" line.content then
        comments := comments.push (makeComment line (dropChars 1 line.content) .standalone)
      else if hasPrefix "%" line.content then
        let parts := line.content.splitOn " " |>.filter (· ≠ "")
        match parts with
        | "%YAML" :: version :: _ => directives := directives.push (.yaml version)
        | "%TAG" :: handle :: uriPrefix :: _ => directives := directives.push (.tag handle uriPrefix)
        | name :: params => directives := directives.push (.reserved (dropChars 1 name) params.toArray)
        | _ => pure ()
      else if line.content = "---" || line.content = "..." then
        pure ()
      else
        lines := lines.push line
    (lines, comments, directives)

private structure RawDocument where
  lines : List (Nat × String) := []
  explicitStart : Bool := false
  explicitEnd : Bool := false
  deriving Repr, Inhabited

private def rawDocumentHasContent (raw : RawDocument) : Bool :=
  raw.lines.any fun (_, text) =>
    let content := (mkLine 0 text).content
    content ≠ "" &&
      !hasPrefix "#" content &&
      !hasPrefix "%" content &&
      content ≠ "---" &&
      content ≠ "..."

private def numberedLines (input : String) : List (Nat × String) :=
  let rawLines := (input.replace "\r\n" "\n").replace "\r" "\n" |>.splitOn "\n"
  let rec go : Nat → List String → List (Nat × String)
    | _, [] => []
    | n, line :: rest => (n, line) :: go (n + 1) rest
  go 1 rawLines

private def splitDocuments (input : String) : Array RawDocument :=
  Id.run do
    let mut docs : Array RawDocument := #[]
    let mut current : RawDocument := {}
    for (n, raw) in numberedLines input do
      let line := mkLine n raw
      if line.content = "---" then
        if rawDocumentHasContent current || current.explicitStart || current.explicitEnd then
          docs := docs.push current
          current := { lines := [], explicitStart := true }
        else
          current := { current with explicitStart := true }
      else if line.content = "..." then
        current := { current with explicitEnd := true }
        docs := docs.push current
        current := {}
      else
        if docs.isEmpty || trim raw ≠ "" || !current.lines.isEmpty || current.explicitStart then
          current := { current with lines := current.lines ++ [(n, raw)] }
    if !current.lines.isEmpty || current.explicitStart || docs.isEmpty then
      docs := docs.push current
    docs

private def parseRawDocument (raw : RawDocument) : Except ParseError YamlDocument := do
  let (lines, comments, directives) := preprocessLines raw.lines
  if lines.isEmpty then
    return { root := .scalar "", leadingComments := comments, directives := directives, explicitStart := raw.explicitStart, explicitEnd := raw.explicitEnd }
  let parsed ← parseBlock directives lines 0 lines[0]!.indent
  if parsed.snd < lines.size then
    throw (err lines[parsed.snd]! "could not parse remaining input")
  return { root := parsed.fst, leadingComments := comments, directives := directives, explicitStart := raw.explicitStart, explicitEnd := raw.explicitEnd }

private def stripUtf8Bom (input : String) : String :=
  if hasPrefix "\uFEFF" input then dropChars 1 input else input

private def encodingError (message : String) : ParseError :=
  { message := message, kind := .invalidEncoding, position := { line := 1, column := 1, offset := 0 } }

def parse (input : String) : Except ParseError YamlStream := do
  let input := stripUtf8Bom input
  let docs ← (splitDocuments input).mapM parseRawDocument
  return { documents := docs }

def parseDocument (input : String) : Except ParseError YamlDocument := do
  let stream ← parse input
  match stream.documents.size with
  | 0 => throw { message := "empty YAML stream", kind := .unexpectedEnd }
  | 1 => pure stream.documents[0]!
  | _ => throw { message := "expected a single YAML document", kind := .unexpectedToken }

def parseByteArray (bytes : ByteArray) : Except ParseError YamlStream :=
  match byteAt? bytes 0, byteAt? bytes 1 with
  | some 0xFE, some 0xFF => .error (encodingError "UTF-16BE input is not supported")
  | some 0xFF, some 0xFE => .error (encodingError "UTF-16LE input is not supported")
  | _, _ =>
      let bytes :=
        match byteAt? bytes 0, byteAt? bytes 1, byteAt? bytes 2 with
        | some 0xEF, some 0xBB, some 0xBF => bytes.extract 3 bytes.size
        | _, _, _ => bytes
      match String.fromUTF8? bytes with
      | some input => parse input
      | none => .error (encodingError "input is not valid UTF-8")

partial def nodeToValue (schema : Schema) : YamlNode → YamlValue
  | .scalar value .plain props _ _ =>
      match props.tag with
      | some tag => .custom tag (.str value)
      | none => Schema.resolvePlain schema value
  | .scalar value _ props _ _ =>
      match props.tag with
      | some tag => .custom tag (.str value)
      | none => .str value
  | .sequence items _ _ => .seq (items.map (nodeToValue schema))
  | .mapping pairs _ _ => .map (pairs.map (fun pair => (nodeToValue schema pair.fst, nodeToValue schema pair.snd)))
  | .alias name _ => .custom "tag:yaml.org,2002:alias" (.str name)

def parseValue (input : String) (schema : Schema := .core) : Except ParseError YamlValue := do
  let stream ← parse input
  let stream ←
    match Yaml.compose stream with
    | .ok stream => pure stream
    | .error err => throw { message := err.message, kind := .unexpectedToken, position := err.position, context := err.path }
  match stream.documents[0]? with
  | some doc =>
      match Yaml.resolve schema doc.root with
      | .ok value => pure value
      | .error err => throw { message := err.message, kind := .invalidScalar, position := err.position, context := err.path }
  | none => throw { message := "empty YAML stream", kind := .unexpectedEnd }

end Parser
end Yaml
