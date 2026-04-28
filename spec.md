**Comprehensive Specification for `lean-yaml`: A Full YAML 1.2.2 Library with Round-Tripping and High-Performance in Lean 4**

This document provides a complete, implementable specification for a novel open-source Lean 4 library (`lean-yaml`) that fills the current gap in the ecosystem (no polished, full-spec YAML 1.2 support exists on Reservoir or in core). It targets **full YAML 1.2.2 compliance**, **lossless round-tripping** (parse → modify minimally → emit yields near-identical output, preserving comments, styles, indentation, anchors, order, and directives where possible), and **high performance** (zero-copy parsing where feasible, streaming support, competitive with C libs like libfyaml or rapidyaml).

### 0. Implementation Status
This project is being implemented as a serious Reservoir-ready Lean package, with correctness and architecture prioritized before broad YAML coverage and performance work.

Current baseline:
- **Lean toolchain**: Done and verified. The project is pinned to `leanprover/lean4:v4.29.1`.
- **Parser dependency**: Done and verified. `fgdorais/lean4-parser` is included and pinned to commit `66271b6`, because Parser `main` currently targets a newer Lean.
- **Lake package**: Done and verified. `lakefile.lean`, `lake-manifest.json`, `Yaml.lean`, library modules, CLI executable, examples, and test executable exist.
- **Core AST**: Done for the v1 foundation and verified. `Yaml/AST.lean` defines source positions/ranges, directives, scalar and collection styles, chomping, comments, node trivia including detached comments, node properties, rich nodes, documents, and streams.
- **High-level value model**: Done and verified. `Yaml/Types.lean` defines ordered `YamlValue` with null, bool, int, float, string, sequence, mapping, and custom-tag values.
- **Parser**: Partially done and verified for the supported subset. `Yaml/Parser.lean` parses UTF-8 strings, UTF-8 `ByteArray` input with BOM handling, multi-document streams, directives, explicit document boundaries, comments, tag handles for parsed scalar properties, anchors, aliases, simple explicit complex keys, block sequences, block mappings, nested flow collections, quoted/plain scalars, and literal/folded block scalar headers with chomping/indent indicators. It imports `lean4-parser`, but the implementation is still mostly hand-written; the next parser milestone is a real token/production layer on Parser combinators.
- **Composer**: Done and verified for initial graph validation. `Yaml/Composer.lean` validates duplicate anchors and undefined aliases.
- **Representation graph**: Done and verified for the first alias-expansion layer. `Yaml/Graph.lean` defines representation document/stream types, expands aliases for the current AST subset, and reports duplicate, undefined, and recursive aliases.
- **Events**: Done and verified for AST-to-event lowering and text event emission. `Yaml/Event.lean` defines `YamlEvent`, lowers streams/documents/nodes to event arrays, and renders events for diagnostics/future low-level emission work.
- **Parser rewrite scaffolding**: Done and verified for the first layer. `Yaml/Parser/Source.lean` and `Yaml/Parser/Token.lean` define source slices, token kinds, token streams, and YAML context markers for the future `lean4-parser` production rewrite.
- **Emitter**: Partially done and verified for the supported subset. `Yaml/Emitter.lean` emits streams, documents, directives, document comments, inline scalar comments, block/flow collections, scalars, aliases, tags, anchors, explicit document start/end, block scalar chomping/indent indicators, and values. Full collection-entry trivia and exact style-preserving output remain incomplete.
- **Schema resolution**: Done and verified for the initial Failsafe/JSON/Core scalar and collection model. `Yaml/Schema.lean` resolves null, bool, decimal and selected Core base-prefixed ints, JSON floats, strings, sequences, mappings, explicit known tags, and custom tags.
- **Serde**: Done and verified for initial common types. `Yaml/Serde.lean` defines `ToYaml` and `FromYaml` with structured `FromYamlError` path context; instances exist for `String`, `Bool`, `Int`, `Nat`, `Float`, `Unit`, `Array`, `List`, and `Option`; helper APIs exist for string-keyed map fields and explicit custom tags.
- **CLI**: Done and verified for the first milestone. `Main.lean` supports `parse`, `value`, `roundtrip`, and `emit-value`; all four commands passed smoke tests.
- **Tests**: Done and verified for the current regression suite. `Test.lean` now aggregates structured `YamlTest.*` modules covering parser/emitter round trips, documents, ByteArray BOM input, block scalars, flow nesting, directive/comment/block-scalar metadata emission, tag handle expansion, simple complex keys, schema differences, composer errors, representation graph alias expansion, event lowering, serde path errors, serde map/tag helpers, and document-oriented streaming APIs.
- **CI and YAML Test Suite harness**: Done and verified for the first executable infrastructure layer. `.github/workflows/ci.yml` runs build/tests/examples/CLI smoke checks and `scripts/yaml-test-suite.sh`; the harness fetches a pinned YAML Test Suite ref, executes classified `pass` cases through the CLI parser, enforces `expectedFail` cases, and reports tracked classification counts from `suite/yaml-test-suite/classification.tsv`.
- **Examples**: Done and verified for the first milestone. `examples/config.lean`, `examples/roundtrip.lean`, and `examples/serde.lean` typecheck/run under `lake env lean`.
- **Documentation**: Done for the current milestone. README documents rationale, toolchain, build/compile/run/test workflows, YAML Test Suite harness use, API surface, examples, remaining work, references, and related materials.

Remaining high-level work:
- Replace or substantially extend the hand-written parser with a `lean4-parser`-based YAML token and production parser.
- Implement full YAML 1.2.2 productions, especially indentation contexts, full tag handle edge cases, flow style edge cases, all complex key forms, restricted block-in-flow cases, and rich diagnostics.
- Attach and emit comments/trivia comprehensively enough for real round-tripping; directive, document-comment, inline scalar comment, and block scalar indicator emission are implemented for the supported subset.
- Expand tag/schema resolution for all remaining YAML 1.2.2 scalar edge cases.
- Add serde deriving.
- Broaden official YAML Test Suite integration beyond the current executable parser pass/fail checks into event/value validation and wider classifications.
- Replace the current document-oriented file streaming helpers with true incremental parser/emitter internals, then add benchmarks and performance work.

### 1. Goals
- **Full compliance**: Pass the official YAML Test Suite (https://github.com/yaml/yaml-test-suite) for 1.2.2, including all edge cases for streams, documents, styles, tags, anchors/aliases, and schemas (Failsafe, JSON, Core).
- **Lossless round-tripping**: Preserve presentation details (comments, block/flow styles, scalar styles, chomping, indentation hints, anchor names, tag shorthands, directives) unless explicitly overridden.
- **High performance**: 
  - Zero-copy parsing on `ByteArray`/`String` slices for large files.
  - Streaming parser/emitter for documents > memory.
  - Benchmarks targeting ≥100 MB/s parse on modern hardware (inspired by libfyaml/ryml).
- **Ergonomic Lean API**: 
  - Low-level event-based / AST for full control.
  - High-level typeclass-based serde (`ToYaml` / `FromYaml`) with deriving macros.
  - Optional lightweight proofs (e.g., round-trip properties).
- **Lean-native**: Pure functional core, IO for streaming, metaprogramming for ergonomics, FFI optional only for ultra-perf extensions.
- **Publishable**: Lake package, Reservoir-ready, with docs, tests, examples, and CLI tool.

**Non-goals** (for v1; extensible later):
- YAML 1.1/1.0 legacy quirks unless explicitly requested.
- YAMLScript or custom extensions.
- Full 1.3+ features (future-proof via version directive).

### 2. Dependencies
- `lean4-parser` (or `fgdorais/lean4-parser`) for combinator-based parsing (highly recommended for maintainability).
- Lean stdlib + Batteries (for `Array`, `ByteArray`, `HashMap`, JSON interop, etc.).
- Optional: `SciLean` or custom numerics for timestamp/float handling; `lean4-cli` for example CLI.

**Status**:
- Done and verified: `lean4-parser` is present as `Parser`, pinned to commit `66271b6` for stable Lean compatibility.
- Done and verified: Lean is pinned to `leanprover/lean4:v4.29.1`.
- Done and verified: The current implementation builds without adding Batteries as a direct dependency; Batteries remains transitive through Parser unless core modules start importing it directly.
- Done and verified for v1 milestone: The CLI intentionally uses lightweight manual parsing; no CLI helper library is required yet.

### 3. Lake Package Structure
```lean
-- lakefile.lean (or .toml)
require lean4-parser from git "https://github.com/fgdorais/lean4-parser" @ "v0.x"

package «lean-yaml» where
  -- ...

-- Root: Yaml.lean
-- Library modules:
--   Yaml/Parser.lean
--   Yaml/AST.lean          -- Rich presentation-preserving AST
--   Yaml/Emitter.lean
--   Yaml/Serde.lean        -- Typeclasses + deriving
--   Yaml/Schema.lean       -- Tag resolution (Failsafe/JSON/Core)
--   Yaml/Types.lean        -- Public data model
-- Tests in test/ (using YAML Test Suite)
-- Examples/ (CLI parser, round-trip demo)
```

**Status**:
- Done and verified: `lakefile.lean`, `lake-manifest.json`, `lean-toolchain`, `Yaml.lean`, and the planned library module names exist.
- Done and verified: `Yaml/Composer.lean` exists as the initial composition/validation phase.
- Done and verified: CLI executable exists as `lean-yaml`.
- Done and verified: Smoke test executable exists as `yamlTest`.
- Done and verified: Examples exist under `examples/`.
- Done and verified: Structured `YamlTest.*` modules back the aggregate `yamlTest` executable.
- Done and verified: CI configuration exists for build, tests, examples, CLI smoke checks, and YAML Test Suite harness.
- Remaining: Add more focused test modules and fixtures as parser coverage grows.

### 4. Core Data Model (YAML AST for Round-Tripping)
Use a **rich serialization-tree AST** that captures *all* presentation details (inspired by YAML processing model: presentation → serialization tree → representation graph).

This enables lossless round-tripping while allowing high-level construction.

```lean
-- Yaml/AST.lean
inductive ScalarStyle where
  | plain | singleQuoted | doubleQuoted | literal | folded
  deriving Repr, Inhabited, DecidableEq

inductive CollectionStyle where
  | block | flow
  deriving Repr, Inhabited, DecidableEq

inductive Chomping where
  | strip | clip | keep
  deriving Repr, Inhabited, DecidableEq

structure NodeProperties where
  tag : Option String  -- full URI or shorthand (preserved)
  anchor : Option String
  deriving Repr, Inhabited

inductive YamlNode where
  | scalar (value : String) (style : ScalarStyle) (props : NodeProperties) (chomping : Option Chomping) (indentHint : Option Nat)
  | sequence (items : Array YamlNode) (style : CollectionStyle) (props : NodeProperties)
  | mapping (pairs : Array (YamlNode × YamlNode)) (style : CollectionStyle) (props : NodeProperties)  -- preserves order
  | alias (name : String)  -- for graph structure
  deriving Repr, Inhabited

structure YamlDocument where
  directives : Array Directive  -- %YAML, %TAG, etc.
  root : YamlNode
  comments : List Comment  -- leading/trailing per document
  deriving Repr, Inhabited

structure YamlStream where
  documents : Array YamlDocument
  deriving Repr, Inhabited

-- Directives, Comment, etc. as inductive or structure with position info for diagnostics.
```

**High-level value model** (for serde, no presentation details):
```lean
inductive YamlValue where
  | null | bool (Bool) | int (Int) | float (Float) | str (String)
  | seq (Array YamlValue) | map (Array (YamlValue × YamlValue))  -- order-preserving
  | custom (tag : String) (value : YamlValue)
```

**Status**:
- Done and verified: Initial rich AST exists with scalar/collection styles, chomping, directives, comments, leading/inline/trailing/detached trivia, source ranges, node properties, aliases, documents, and streams.
- Done and verified: Ordered `YamlValue` exists for high-level APIs and serde.
- Remaining: Refine comment attachment semantics so comments can be associated with exact nodes, document boundaries, and collection entries.
- Remaining: Decide whether scalar values should later store source slices for zero-copy parsing in addition to decoded `String` values.
- Done and verified for initial validation: composition layer validates duplicate anchors and undefined aliases.
- Done and verified for first graph layer: `composeGraph` / `expandAliases` build a representation stream with aliases expanded for the current AST subset and detect recursive aliases.
- Remaining: Expand composition into full YAML representation graph construction with node identity and configurable alias preservation/expansion modes.

### 5. Parser Specification
- **Input**: `ByteArray` or `String` (UTF-8 default; BOM detection for UTF-16/32).
- **Output**: `YamlStream` (rich AST) + optional `YamlValue` (via schema).
- **Implementation**:
  - Recursive-descent or combinator parser following YAML BNF (use `lean4-parser` for `Parser` monad with indentation context, line prefixes, flow/block contexts).
  - Zero-copy: Scalars reference input slices (`SubString` or `ByteArray` slices).
  - Handles: streams, multiple documents, directives, properties (tags/anchors), aliases (resolve during composition), all scalar/collection styles, comments (stored but ignored in content).
  - Tag resolution: Configurable schema (Failsafe → !!str/seq/map; JSON/Core regex-based for plain scalars: null, bool, int, float, timestamp, etc.).
  - Error handling: Rich diagnostics with source locations (line/col, context).
  - Streaming mode: Yield documents incrementally via `IO` or `EIO`.

**Key productions to implement** (high-level):
- `l-yaml-stream`, `l-document`, `ns-flow-node`, block mappings/sequences, scalar styles with escapes/folding/chomping.

**Performance**: Memoization where needed (Lean parser supports it); benchmark against official test suite files.

**Status**:
- Done and verified: Public `parse : String -> Except ParseError YamlStream` and `parseValue : String -> Schema -> Except ParseError YamlValue` exist.
- Done and verified: `parseDocument : String -> Except ParseError YamlDocument` exists.
- Done and verified: `parseByteArray : ByteArray -> Except ParseError YamlStream` exists, strips UTF-8 BOM input, rejects UTF-16 BOMs, and rejects invalid UTF-8.
- Done and verified: Current parser handles the supported subset: multi-document streams, explicit document starts/ends, `%YAML` and `%TAG` directives, scalars, simple quotes, simple explicit complex keys, block mappings, block sequences, nested flow collections, comments, tag handle expansion for parsed scalar properties, anchors, aliases, literal/folded block scalar headers, chomping indicators, and indentation hints.
- Done and verified: Parse errors include line/column-capable `ParseError` structure.
- Remaining: Build the real `lean4-parser` token/production parser rather than relying on the current line-oriented subset parser.
- Done and verified for parser rewrite scaffolding: source slices, token kinds, token streams, and YAML parse context markers exist under `Yaml/Parser/`.
- Remaining: Implement full YAML 1.2.2 indentation contexts and productions: `l-yaml-stream`, `l-document`, `ns-flow-node`, all block/flow restrictions, complete scalar escapes/folding rules, all complex key forms, full tag handle edge cases, and edge-case diagnostics.
- Remaining: Add source-slice strategy for zero-copy parsing.
- Done and verified for initial IO ergonomics: document-oriented `parseStreamFromFile` and `emitStreamToFile` helpers exist.
- Remaining: Replace those helpers with true incremental parser/emitter internals.

### 6. Emitter Specification
- **Input**: `YamlStream` or `YamlValue` + optional style overrides.
- **Output**: `String` or streamed `IO` writer (UTF-8).
- **Round-tripping guarantees**:
  - Re-emit exact styles, comments, indentation, chomping, anchors/aliases, tag shorthands, and directives from the AST.
  - Order of mapping pairs and sequence items preserved.
  - Minimal changes: Only normalize line breaks to LF; escape as-needed.
- **Options**:
  - `pretty : Bool` (force block style, canonical tags).
  - Custom indentation, flow thresholds, etc.
- **Implementation**: Tree-walking emitter with context (indent level, flow/block). Use `String` builder or `IO.FS.Stream` for zero-allocation where possible.

**libfyaml-inspired layering**: Event-stream emitter for low-level control.

**Status**:
- Done and verified: Public `emit : YamlStream -> EmitOptions -> String` and `emitValue : YamlValue -> EmitOptions -> String` exist.
- Done and verified: Public `emitDocument : YamlDocument -> EmitOptions -> String` exists.
- Done and verified: Current emitter handles directives, document comments, inline scalar comments, block/flow sequences, block/flow mappings, scalars, aliases, tags, anchors, explicit document starts/ends, block scalar chomping/indent indicators, documents, streams, values, and diagnostic event rendering for the supported subset.
- Done and verified: Mapping order is preserved through arrays of pairs.
- Remaining: Emit collection-entry trivia, trailing trivia, full block scalar formatting details, and exact original styles.
- Remaining: Add configurable flow thresholds and richer pretty-printing behavior.
- Done and verified for initial IO ergonomics: `emitStreamToFile` writes documents to an `IO.FS.Handle`.
- Remaining: Add a lower-level streamed writer API over emission events.
- Done and verified for first event layer: `YamlEvent`, `eventsOfStream`, and `eventsOfDocument` lower the current AST to event arrays.
- Done and verified for diagnostic event output: `emitEvents` and `emitStreamEvents` render event streams as text.
- Remaining: Add event parser and YAML-producing low-level event-stream emitter.

### 7. Serialization / Deserialization API (`Yaml/Serde.lean`)
```lean
class ToYaml (α : Type) where
  toYaml : α → YamlValue  -- or directly to YamlNode with style hints

class FromYaml (α : Type) where
  fromYaml : YamlValue → Except String α

-- Deriving support via metaprogramming (quote + macros)
macro "deriving instance" ToYaml for t:ident : command
-- Example:
structure Config where
  name : String
  ports : Array Nat
deriving ToYaml, FromYaml
```

- Automatic tag handling for custom types (`!my.app/Config`).
- Round-trip proof helpers: `roundTripProp : ∀ (v : α), fromYaml (toYaml v) = pure v` (optional `Prop`).

**Status**:
- Done and verified: `ToYaml` and `FromYaml` classes exist.
- Done and verified: Instances exist for `String`, `Bool`, `Int`, `Nat`, `Float`, `Unit`, `Array`, `List`, and `Option`.
- Done and verified: `FromYaml` returns structured `FromYamlError` with path context.
- Remaining: Add instances for more common types where appropriate.
- Remaining: Add deriving support for structures and inductives.
- Done and verified for the first helper layer: `withTag` and `fromTagged` provide explicit custom tag handling for user APIs.
- Remaining: Integrate custom tags with deriving and richer user-type metadata.
- Remaining: Add optional round-trip proof helpers after the API stabilizes.

### 8. Public API Surface (`Yaml.lean`)
```lean
def parse (input : String) : Except ParseError YamlStream
def parseValue (input : String) (schema := Schema.core) : Except ParseError YamlValue

def emit (doc : YamlDocument) (opts : EmitOptions := {}) : String
def emitValue (v : YamlValue) (opts : EmitOptions := {}) : String

-- Streaming
def parseStream [Monad m] [MonadLift IO m] ... 
def emitStream ...

-- CLI example: lean-yaml parse file.yaml --roundtrip
```

**Status**:
- Done and verified: `Yaml.parse`, `Yaml.parseValue`, `Yaml.emit`, and `Yaml.emitValue` exist.
- Done and verified: `Yaml.parseDocument`, `Yaml.parseByteArray`, `Yaml.compose`, `Yaml.resolve`, and `Yaml.emitDocument` exist.
- Done and verified as placeholders: `Yaml.parseStream` and `Yaml.emitStream` exist as IO-wrapped non-streaming APIs.
- Done and verified for initial IO ergonomics: `Yaml.parseStreamFromFile` and `Yaml.emitStreamToFile` process whole parsed documents through callbacks/file handles.
- Done and verified: CLI supports `parse`, `value`, `roundtrip`, and `emit-value`.
- Remaining: Replace placeholder streaming APIs with true incremental parser/emitter implementations.
- Remaining: Consider whether `emit` should accept a `YamlStream` only long-term, or also provide overloaded/convenience document forms beyond `emitDocument`.

### 9. Performance & Implementation Notes
- **Zero-copy core**: Parser works on immutable input buffer; AST scalars are slices.
- **Memory**: Efficient `Array`/`HashMap` for mappings (order preserved via `Array` of pairs).
- **Benchmarks**: Include `hyperfine` via LeanBench; target large configs, Kubernetes YAML, etc.
- **FFI fallback** (optional v2): Bind to libfyaml for ultra-perf, with safe Lean wrappers.
- **Concurrency**: Pure core + `Task` for parallel document parsing.

**Status**:
- Done and verified: Ordered mappings use arrays of pairs.
- Done and verified: `ByteArray` entry point exists for UTF-8 input.
- Remaining: Zero-copy parsing is not implemented yet; current scalar values are decoded `String`s.
- Remaining: No benchmark harness yet.
- Remaining: No true incremental parser implementation yet; current file helpers stream document callbacks after parsing.
- Remaining: No FFI plan should be attempted until the pure Lean implementation is substantially complete.

### 10. Testing & Compliance
- **Unit tests**: Official YAML Test Suite (all cases marked as "ok" for 1.2).
- **Round-trip tests**: Parse → emit → parse == original (with style/comments).
- **Fuzzing**: Property-based (Lean’s `Test` or external).
- **Edge cases**: Anchors/aliases (cycles, forward refs), complex keys, explicit tags, BOM, non-UTF8 detection, invalid streams.
- **Coverage**: 100% of YAML 1.2.2 productions.

**Status**:
- Done and verified: Smoke/regression executable `yamlTest` exists and passes.
- Done and verified: `yamlTest` covers nested mapping/sequence round trip, document parsing, multi-document streams, explicit document start/end, UTF-8 ByteArray BOM parsing, literal block scalars with chomping, nested flow collections, directive/comment/block-scalar metadata emission, tag handle expansion, simple explicit complex keys, Core vs JSON schema differences, composer alias validation, representation graph alias expansion, event lowering, serde path-aware failures, serde map/tag helpers, and document-oriented streaming helpers.
- Done and verified: Manual CLI smoke tests pass for `parse`, `value`, `roundtrip`, and `emit-value`.
- Done and verified: Unit tests are organized under `YamlTest.*` modules with an aggregate executable.
- Done and verified for first infrastructure layer: YAML Test Suite fetch/classification harness exists.
- Done and verified for first executable harness layer: classified `pass` cases are parsed by the CLI and `expectedFail` cases are enforced.
- Remaining: Broaden YAML Test Suite classifications and validate expected event/value outputs, not only parser success/failure.
- Remaining: Add round-trip tests that compare AST preservation, not just emitted text for simple cases.
- Remaining: Add invalid-input diagnostics tests.
- Remaining: Add property/fuzz tests once parser behavior is broader.

### 11. Examples & Documentation
- `examples/config.lean`: Parse Kubernetes-style YAML → Lean struct → round-trip.
- `examples/cli.lean`: Full CLI tool (like `yq` subset).
- Full Haddock-style docs + tutorial in README.

**Status**:
- Done and verified: README now documents project rationale, toolchain, build/compile/run/test workflows, CLI smoke checks, examples, public API, module layout, implemented subset, remaining work, references, and related projects.
- Done and verified: CI configuration exists for build, tests, examples, CLI smoke checks, and YAML Test Suite harness.
- Done and verified: CLI exists as the initial example of executable use.
- Done and verified: `examples/config.lean`, `examples/roundtrip.lean`, and `examples/serde.lean` exist and typecheck/run under `lake env lean`.
- Remaining: Add richer examples once parser coverage is less provisional.
- Remaining: Add API documentation comments throughout public modules.
- Remaining: Add tutorial once parser coverage is less provisional.

### 12. Roadmap & Novelty
- v0.1: Parser + basic emitter + serde.
- v0.2: Full round-trip + streaming + benchmarks.
- Novel contributions: Lean-first metaprogramming-derived serde + optional proofs of round-tripping + integration with Lean widgets for YAML visualizer.

**Status**:
- Partially completed and verified v0.1: project scaffold, AST, value model, parser for the supported subset, composer validation, emitter, schema resolution, serde typeclasses, CLI, examples, and smoke/regression tests are implemented and build successfully.
- Remaining v0.1: Parser-combinator production layer, broader YAML subset, better diagnostics, executable YAML Test Suite cases, serde deriving, and public API cleanup.
- Remaining v0.2: Full round-trip fidelity, comprehensive comment/trivia preservation, streaming APIs, benchmark suite, and YAML Test Suite coverage expansion.
- Remaining future work: serde deriving, proof helpers, optional widgets/visualizer, and possible FFI acceleration.

This spec positions `lean-yaml` as a **production-grade, community-standard** library that leverages Lean’s strengths (performance, metaprogramming, FP purity) while being immediately useful. It would be a flagship project for non-mathematicians entering Lean.

### 13. Remaining Functionality And Completion Requirements

This section is the current close-out checklist for moving from the verified supported subset to the full specification above.

#### 13.1 Parser Compliance
**Done and verified**:
- UTF-8 string and `ByteArray` entry points, UTF-8 BOM stripping, invalid UTF-8 rejection, and UTF-16 BOM rejection.
- Multi-document streams, explicit document start/end markers, directive/comment preambles, `%YAML` and `%TAG` directive parsing.
- Block mappings, block sequences, nested flow collections, simple explicit complex keys, anchors, aliases, plain/single/double quoted scalars, and literal/folded block scalar headers with chomping/indent indicators.
- Basic tag handle expansion for scalar properties in the supported subset.

**Remaining**:
- Replace the line-oriented parser with a real YAML token and production parser on top of `lean4-parser`.
- Implement YAML 1.2.2 indentation contexts, `l-yaml-stream`, `l-document`, flow/block productions, block-in-flow restrictions, all complex-key forms, all tag-handle edge cases, full scalar escaping, folding, chomping, and diagnostic context.

**What completion requires**:
- Extend the existing source/token/context scaffolding into a real lexer with source ranges and trivia retention.
- Encode YAML contexts explicitly, including block-in, block-out, flow-in, flow-out, block-key, and flow-key behavior.
- Port YAML 1.2.2 productions incrementally, backed by YAML Test Suite fixtures.
- Add invalid-input diagnostics tests for indentation, directives, malformed flow collections, invalid escapes, unknown tags, and unfinished documents.

#### 13.2 Representation Graph And Round-Tripping
**Done and verified**:
- Rich AST foundation records styles, directives, comments, trivia containers, tags, anchors, aliases, document boundaries, source ranges, and ordered mappings.
- Composer validates duplicate anchors and undefined aliases.
- Representation graph APIs expand aliases for the current AST subset and diagnose recursive aliases.
- Event APIs lower the current AST to event arrays.
- Emitter preserves directives, document comments, inline scalar comments, block/flow collections, scalar styles for supported nodes, tags, anchors, aliases, document start/end markers, mapping order, and block scalar chomping/indent indicators in the supported subset.

**Remaining**:
- Full representation graph construction with node identity and configurable alias preservation/expansion modes.
- Exact comment/trivia attachment for nodes, collection entries, document boundaries, and trailing comments.
- Exact original-style emission for arbitrary supported YAML.
- Event parser and low-level event stream emitter.

**What completion requires**:
- Add a representation graph data structure separate from the presentation AST.
- Track anchor definitions by node identity and expand or preserve aliases according to API mode.
- Define deterministic trivia attachment rules and test them against real-world YAML.
- Add AST-preserving round-trip tests for comments, directives, tags, anchors, aliases, scalar styles, indentation hints, chomping, collection styles, and mapping order.
- Extend the existing event types and diagnostic renderer into parse-event support and a YAML-producing event emitter.

#### 13.3 Schema And Serde
**Done and verified**:
- Failsafe, JSON, and Core schema basics for null, bool, ints including selected Core base-prefixed forms, JSON floats, strings, sequences, mappings, explicit known tags, and custom tags.
- `ToYaml` and `FromYaml` classes.
- Instances for `String`, `Bool`, `Int`, `Nat`, `Float`, `Unit`, `Array`, `List`, and `Option`.
- Path-aware `FromYamlError`.
- `lookupKey?`, `fromMapField`, `withTag`, and `fromTagged` helpers.

**Remaining**:
- Remaining YAML 1.2.2 scalar edge cases for JSON/Core schemas.
- More common instances where appropriate.
- Deriving support for structures and simple inductives.
- Custom tag integration in deriving.
- Optional round-trip proof helpers after APIs stabilize.

**What completion requires**:
- Replace ad hoc scalar checks with spec-driven recognizers for YAML 1.2.2 schemas.
- Design deriving output shape for structures, enums, sum types, optional fields, defaults, and custom tags.
- Add macro tests that compile example derived instances and runtime tests for nested structures and inductives.
- Define proof-helper statements only after `ToYaml`/`FromYaml` behavior is stable enough to avoid churn.

#### 13.4 Streaming, Performance, And Optional FFI
**Done and verified**:
- Public `parseStream` and `emitStream` placeholders exist.
- `parseStreamFromFile` and `emitStreamToFile` provide initial document-oriented IO ergonomics.
- Ordered mappings are represented as arrays of pairs.
- Source-slice scaffolding exists for zero-copy parser work.

**Remaining**:
- True incremental parser and emitter.
- Zero-copy scalar storage or source-slice strategy.
- Benchmark harness and throughput tracking.
- Optional FFI acceleration only after pure Lean correctness is substantially complete.

**What completion requires**:
- Redesign parser state to consume chunks and yield documents/events without requiring the full input string.
- Add a source-slice scalar representation strategy with decoded-string fallback for escaped scalars.
- Create large YAML fixtures, Kubernetes-style fixtures, YAML Test Suite benchmark subsets, and reproducible benchmark commands.
- Establish a pure Lean baseline before introducing any optional C/C++ backend.

#### 13.5 Testing, CI, Docs, And Release Readiness
**Done and verified**:
- `lake build` passes.
- `lake exe yamlTest` passes.
- CLI smoke tests pass for `parse`, `value`, `roundtrip`, and `emit-value`.
- Examples typecheck/run under `lake env lean`.
- README documents rationale, toolchain, build/compile/run/test workflows, API surface, examples, current status, remaining work, and references.
- Structured `YamlTest.*` modules back the aggregate test executable.
- CI configuration covers build, tests, examples, CLI smoke checks, and YAML Test Suite harness.
- YAML Test Suite fetch/classification infrastructure exists.

**Remaining**:
- Add AST-preserving round-trip tests, invalid diagnostics tests, schema tests, serde deriving tests, property/fuzz tests, benchmark baselines, and CLI smoke tests in CI.
- Add API documentation comments, richer examples, tutorial material, and Reservoir metadata.

**What completion requires**:
- Add more focused test modules as parser, emitter, schema, serde deriving, and streaming coverage grows.
- Extend the existing YAML Test Suite harness to compare expected events/values and steadily classify more upstream cases.
- Add property/fuzz tests and benchmark baselines once parser behavior is broader.
- Add Reservoir-ready metadata once the API surface and supported subset are documented clearly.
