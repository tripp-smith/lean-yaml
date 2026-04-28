import Yaml.AST
import Yaml.Error
import Yaml.Parser.Source

namespace Yaml
namespace Parser

inductive YamlContext where
  | blockIn
  | blockOut
  | flowIn
  | flowOut
  | blockKey
  | flowKey
  deriving Repr, Inhabited, DecidableEq

inductive TokenKind where
  | streamStart
  | streamEnd
  | documentStart
  | documentEnd
  | directive
  | comment
  | scalar
  | alias
  | anchor
  | tag
  | blockSequenceEntry
  | mappingKey
  | mappingValue
  | flowSequenceStart
  | flowSequenceEnd
  | flowMappingStart
  | flowMappingEnd
  | flowEntry
  | indentation
  | lineBreak
  deriving Repr, Inhabited, DecidableEq

structure Token where
  kind : TokenKind
  text : String := ""
  range : SourceRange := {}
  context : Option YamlContext := none
  deriving Repr, Inhabited, DecidableEq

structure TokenStream where
  tokens : Array Token := #[]
  source : SourceBuffer := { input := "" }
  deriving Repr, Inhabited

namespace Token

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

private def countIndent (s : String) : Nat :=
  let rec go : List Char → Nat
    | [] => 0
    | c :: cs => if c = ' ' then go cs + 1 else 0
  go s.toList

private def leadingWhitespace (s : String) : String :=
  let rec go (acc : List Char) : List Char → List Char
    | [] => acc.reverse
    | c :: cs =>
        if c = ' ' || c = '\t' then go (c :: acc) cs else acc.reverse
  String.ofList (go [] s.toList)

private def dropChars (n : Nat) (s : String) : String :=
  String.ofList (s.toList.drop n)

private def takeChars (n : Nat) (s : String) : String :=
  String.ofList (s.toList.take n)

private def err (line column offset : Nat) (message : String) (kind : ParseErrorKind) (context : Array String := #[]) : ParseError :=
  { message, kind, position := { line, column, offset }, context }

private def mkRange (line startColumn stopColumn startOffset stopOffset : Nat) : SourceRange :=
  { start := { line, column := startColumn, offset := startOffset }
    stop := { line, column := stopColumn, offset := stopOffset } }

private def mkToken (kind : TokenKind) (text : String) (range : SourceRange) (context : Option YamlContext := none) : Token :=
  { kind, text, range, context }

private def lineContext (indent : Nat) (inFlow : Bool) : YamlContext :=
  if inFlow then .flowIn
  else if indent = 0 then .blockOut
  else .blockIn

private def directiveKind? (content : String) : Except String Unit :=
  let parts := content.splitOn " " |>.filter (· ≠ "")
  match parts with
  | "%YAML" :: version :: [] =>
      if version = "1.2" || version = "1.2.2" then pure ()
      else throw s!"unsupported YAML directive version {version}"
  | "%YAML" :: _ => throw "expected %YAML version"
  | "%TAG" :: handle :: uriPrefix :: [] =>
      if handle = "" || uriPrefix = "" then
        throw "expected %TAG handle and prefix"
      else
        pure ()
  | "%TAG" :: _ => throw "expected %TAG handle and prefix"
  | name :: _ =>
      if hasPrefix "%" name then pure () else throw "expected directive"
  | [] => throw "expected directive"

private def scanFlowChars (lineNo indent lineOffset : Nat) (content : String) (initialDepth : Nat) :
    Except ParseError (Array Token × Nat) := do
  let rec go (chars : List Char) (idx : Nat) (depth : Nat) (quote : Option Char) (tokens : Array Token) :
      Except ParseError (Array Token × Nat) := do
    match chars with
    | [] =>
        match quote with
        | some q =>
            throw (err lineNo (indent + idx + 1) (lineOffset + indent + idx) s!"unterminated quoted scalar {q}" .invalidScalar #["flow"])
        | none => pure (tokens, depth)
    | c :: rest =>
        let col := indent + idx + 1
        let off := lineOffset + indent + idx
        match quote with
        | some q =>
            if c = '\\' && q = '"' then
              match rest with
              | [] => throw (err lineNo col off "unterminated escape sequence" .invalidScalar #["double-quoted scalar"])
              | esc :: rest' =>
                  let valid := ['0','a','b','t','n','v','f','r','e','"','/','\\','N','_','L','P','x','u','U'].contains esc
                  if valid then go rest' (idx + 2) depth quote tokens
                  else throw (err lineNo (col + 1) (off + 1) s!"invalid escape sequence \\{esc}" .invalidScalar #["double-quoted scalar"])
            else if c = q then
              go rest (idx + 1) depth none tokens
            else
              go rest (idx + 1) depth quote tokens
        | none =>
            if c = '#' then
              pure (tokens, depth)
            else if c = '\'' || c = '"' then
              go rest (idx + 1) depth (some c) tokens
            else
              let range := mkRange lineNo col (col + 1) off (off + 1)
              match c with
              | '[' =>
                  go rest (idx + 1) (depth + 1) none (tokens.push (mkToken .flowSequenceStart "[" range (some .flowIn)))
              | '{' =>
                  go rest (idx + 1) (depth + 1) none (tokens.push (mkToken .flowMappingStart "{" range (some .flowIn)))
              | ']' =>
                  if depth = 0 then
                    throw (err lineNo col off "unexpected flow sequence end" .unexpectedToken #["flow"])
                  go rest (idx + 1) (depth - 1) none (tokens.push (mkToken .flowSequenceEnd "]" range (some .flowIn)))
              | '}' =>
                  if depth = 0 then
                    throw (err lineNo col off "unexpected flow mapping end" .unexpectedToken #["flow"])
                  go rest (idx + 1) (depth - 1) none (tokens.push (mkToken .flowMappingEnd "}" range (some .flowIn)))
              | ',' =>
                  go rest (idx + 1) depth none (tokens.push (mkToken .flowEntry "," range (some .flowIn)))
              | ':' =>
                  go rest (idx + 1) depth none (tokens.push (mkToken .mappingValue ":" range (some (if depth = 0 then .blockIn else .flowIn))))
              | '-' =>
                  let entry :=
                    if idx = 0 then
                      tokens.push (mkToken .blockSequenceEntry "-" range (some .blockIn))
                    else
                      tokens
                  go rest (idx + 1) depth none entry
              | _ => go rest (idx + 1) depth none tokens
  go content.toList 0 initialDepth none #[]

private def tokenizeLine (lineNo lineOffset depth : Nat) (raw : String) : Except ParseError (Array Token × Nat) := do
  let indent := countIndent raw
  let indentationText := leadingWhitespace raw
  if indentationText.toList.contains '\t' then
    throw (err lineNo 1 lineOffset "tabs are not allowed for indentation" .invalidIndentation #["indentation"])
  let content := trim (dropChars indent raw)
  if content = "" then
    let range := mkRange lineNo 1 (raw.length + 1) lineOffset (lineOffset + raw.length)
    return (#[mkToken .lineBreak "" range], depth)
  let startColumn := indent + 1
  let startOffset := lineOffset + indent
  let fullRange := mkRange lineNo startColumn (raw.length + 1) startOffset (lineOffset + raw.length)
  let ctx := lineContext indent (depth > 0)
  if hasPrefix "#" content then
    return (#[mkToken .comment (dropChars 1 content |> trim) fullRange (some ctx), mkToken .lineBreak "" fullRange], depth)
  else if hasPrefix "%" content then
    match directiveKind? content with
    | .ok () => return (#[mkToken .directive content fullRange (some .blockOut), mkToken .lineBreak "" fullRange], depth)
    | .error message => throw (err lineNo startColumn startOffset message .invalidDirective #["directive"])
  else if content = "---" then
    return (#[mkToken .documentStart content fullRange (some .blockOut), mkToken .lineBreak "" fullRange], depth)
  else if content = "..." then
    return (#[mkToken .documentEnd content fullRange (some .blockOut), mkToken .lineBreak "" fullRange], depth)
  else
    let scalar := mkToken .scalar content fullRange (some ctx)
    let indentToken :=
      if indent = 0 then #[]
      else #[mkToken .indentation (toString indent) (mkRange lineNo 1 startColumn lineOffset startOffset) (some ctx)]
    let propTokens :=
      content.splitOn " " |>.filterMap fun part =>
        if hasPrefix "&" part && part.length > 1 then
          some (mkToken .anchor part fullRange (some ctx))
        else if hasPrefix "*" part && part.length > 1 then
          some (mkToken .alias part fullRange (some ctx))
        else if hasPrefix "!" part && part.length > 1 then
          some (mkToken .tag part fullRange (some ctx))
        else
          none
    let (flowTokens, depth) ← scanFlowChars lineNo indent lineOffset content depth
    return (indentToken ++ #[scalar] ++ propTokens.toArray ++ flowTokens ++ #[mkToken .lineBreak "" fullRange], depth)

private def numberedLines (input : String) : List String :=
  (input.replace "\r\n" "\n").replace "\r" "\n" |>.splitOn "\n"

def lex (input : String) : Except ParseError TokenStream := do
  let source := SourceBuffer.ofString input
  let input := if hasPrefix "\uFEFF" input then dropChars 1 input else input
  let mut tokens : Array Token := #[mkToken .streamStart "" (mkRange 1 1 1 0 0) (some .blockOut)]
  let mut lineNo := 1
  let mut offset := 0
  let mut depth := 0
  for raw in numberedLines input do
    let (lineTokens, nextDepth) ← tokenizeLine lineNo offset depth raw
    tokens := tokens ++ lineTokens
    depth := nextDepth
    offset := offset + raw.length + 1
    lineNo := lineNo + 1
  if depth ≠ 0 then
    throw (err (lineNo - 1) 1 offset "unterminated flow collection" .unexpectedEnd #["flow"])
  let stop := { line := lineNo, column := 1, offset := offset }
  tokens := tokens.push (mkToken .streamEnd "" { start := stop, stop := stop } (some .blockOut))
  pure { tokens, source }

end Token

def lex (input : String) : Except ParseError TokenStream :=
  Token.lex input

end Parser
end Yaml
