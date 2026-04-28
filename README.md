# lean-yaml

`lean-yaml` is a Lean 4 YAML library aimed at YAML 1.2.2 compliance,
round-trippable syntax trees, schema-aware values, typeclass-based serde, and a
small command-line tool.

The package is pre-v1. The current implementation is useful for a supported
YAML subset and establishes the public architecture, but it is not yet a full
YAML 1.2.2 implementation. Correctness and API shape are being prioritized
before zero-copy parsing, true incremental streaming, benchmarks, and broad YAML
Test Suite coverage.

## Rationale

Lean projects increasingly need to read and write configuration, generated
metadata, CI files, Kubernetes-style manifests, and data formats used by
non-Lean tools. A Lean-native YAML package should support two different use
cases:

- High-level parsing into `YamlValue` for configuration and data exchange.
- Rich syntax-tree parsing for editors, linters, generators, refactoring tools,
  and near-lossless round-tripping.

This project follows YAML's processing-model split between presentation,
serialization tree, and representation graph. The rich AST keeps style,
directive, comment, tag, anchor, alias, and document-boundary information where
the current parser can capture it, while `YamlValue` provides a simpler
schema-resolved model for application code and serde.

The long-term goal is a Reservoir-ready Lean package that can pass the official
YAML 1.2.2 test suite, provide ergonomic Lean APIs, and later grow optional
performance work such as zero-copy parsing, benchmarked streaming, and possible
FFI acceleration.

## Current Status

Implemented and verified with `lake build`, `lake exe yamlTest`, example
typechecks, CLI smoke checks, and `bash scripts/yaml-test-suite.sh`:

- Lake package, public library root, CLI executable, examples, and test
  executable.
- Lean toolchain pinned to `leanprover/lean4:v4.29.1`.
- `fgdorais/lean4-parser` dependency pinned to commit `66271b6`.
- Rich AST with source positions/ranges, directives, comments, node trivia,
  scalar and collection styles, chomping, tags, anchors, aliases, documents,
  and streams.
- Ordered high-level `YamlValue` model with null, bool, int, float, string,
  sequence, mapping, and custom-tag values.
- Parser support for UTF-8 strings, UTF-8 `ByteArray` input, UTF-8 BOM
  stripping, UTF-16 BOM rejection, invalid UTF-8 rejection, multi-document
  streams, `%YAML` and `%TAG` directives, directive/comment preambles before
  `---`, explicit `---` and `...`, block sequences, block mappings, nested flow
  sequences/maps, simple explicit complex keys, plain/single/double quoted
  scalars, literal/folded block scalar headers with chomping and indentation
  hints, comments, tag handle expansion for scalar properties, anchors, and
  aliases.
- Composer validation for duplicate anchors and undefined aliases.
- Representation graph composition API with alias expansion and recursive alias
  diagnostics for the current AST subset.
- Failsafe, JSON, and Core schema resolution for strings, null, bool, decimal
  and selected Core base-prefixed ints, JSON floats, sequences, mappings,
  explicit known tags, and custom tags.
- Emitter support for streams, documents, directives, document comments, inline
  scalar comments, block/flow collections, scalar styles, aliases, tags,
  anchors, explicit document start/end, block scalar chomping/indent indicators,
  and `YamlValue` output.
- `ToYaml` / `FromYaml` instances for `String`, `Bool`, `Int`, `Nat`, `Float`,
  `Unit`, `Array`, `List`, and `Option`, with path-aware `FromYamlError`.
- Serde helpers for string-keyed map fields and explicit custom tags:
  `lookupKey?`, `fromMapField`, `withTag`, and `fromTagged`.
- Public IO convenience helpers `parseStreamFromFile` and `emitStreamToFile`.
  These are document-oriented wrappers around current whole-input parsing, not
  true incremental parsers yet.
- Event lowering from `YamlStream`/`YamlDocument` to low-level `YamlEvent`
  streams plus a text event emitter for diagnostics and future low-level
  emission work.
- Parser source-slice, token, and context scaffolding for the planned
  `lean4-parser` production rewrite.
- CLI commands: `parse`, `value`, `roundtrip`, and `emit-value`.
- Structured regression tests under `YamlTest.*` for parser/emitter round trips,
  documents, ByteArray BOM handling, block scalars, flow nesting,
  directive/comment/block-scalar metadata emission, tag handle expansion, simple
  complex keys, schema differences, composer errors, representation graph alias
  expansion, event lowering, serde errors, serde helpers, and streaming helpers.
- CI configuration for build, unit tests, examples, CLI smoke checks, and the
  YAML Test Suite harness.
- YAML Test Suite fetch/classification harness with executable `pass` cases and
  tracked pass/expected-fail/unsupported metadata.

Not implemented yet:

- Full YAML 1.2.2 grammar and all edge cases.
- A real `lean4-parser` YAML token/production pipeline; the parser still uses
  mostly hand-written line-oriented code.
- Full indentation contexts, all block/flow restrictions, full scalar escaping,
  folding, chomping, and all complex-key forms.
- Full tag directive semantics and all tag handle edge cases.
- Complete YAML 1.2.2 schema scalar edge cases.
- Full comment/trivia attachment for nodes, document boundaries, and collection
  entries.
- Exact presentation-preserving emission for arbitrary input.
- Serde deriving for structures and inductives.
- True incremental streaming parser/emitter internals.
- Zero-copy scalar slices, benchmarks, fuzz/property tests, broad YAML Test
  Suite case coverage, and Reservoir publishing metadata.

## Toolchain

- Lean: `leanprover/lean4:v4.29.1`
- Package source directory: repository root
- Dependency lock file: `lake-manifest.json`
- Parser dependency: `fgdorais/lean4-parser` at commit `66271b6`

Install Lean with `elan`, then verify the local toolchain:

```bash
elan toolchain install leanprover/lean4:v4.29.1
lean --version
lake --version
```

## Build And Compile

Fetch or refresh dependencies:

```bash
lake update
```

Build the library and default target:

```bash
lake build
```

Build the CLI and test executables:

```bash
lake build lean-yaml yamlTest
```

Compile or typecheck individual files in the Lake environment:

```bash
lake env lean Yaml.lean
lake env lean examples/config.lean
lake env lean examples/roundtrip.lean
lake env lean examples/serde.lean
```

Clean generated build output:

```bash
lake clean
```

## Run The CLI

The executable is `lean-yaml`:

```bash
lake exe lean-yaml parse config.yaml
lake exe lean-yaml value config.yaml
lake exe lean-yaml roundtrip config.yaml
lake exe lean-yaml emit-value config.yaml
```

Commands:

- `parse`: parse YAML and print the rich `YamlStream` representation.
- `value`: parse, compose, resolve with the Core schema, and print `YamlValue`.
- `roundtrip`: parse and emit the AST.
- `emit-value`: parse to `YamlValue` and emit normalized YAML.

Example:

```bash
cat > /tmp/config.yaml <<'YAML'
%YAML 1.2
---
# service config
name: lean-yaml
enabled: true
ports:
  - 80
  - 443
YAML

lake exe lean-yaml parse /tmp/config.yaml
lake exe lean-yaml value /tmp/config.yaml
lake exe lean-yaml roundtrip /tmp/config.yaml
lake exe lean-yaml emit-value /tmp/config.yaml
```

## Run Tests

Run the current regression suite:

```bash
lake exe yamlTest
```

Run the YAML Test Suite harness. This fetches the pinned upstream suite into
`build/yaml-test-suite`, executes cases marked `pass`, enforces cases marked
`expectedFail`, and ignores cases marked `unsupported`:

```bash
bash scripts/yaml-test-suite.sh
```

Before submitting changes, run:

```bash
lake build
lake exe yamlTest
bash scripts/yaml-test-suite.sh
```

CLI smoke checks:

```bash
tmp=/tmp/lean-yaml-smoke.yaml
printf '%s\n' '---' 'name: lean-yaml' 'enabled: true' 'ports:' '  - 80' '  - 443' > "$tmp"
lake exe lean-yaml parse "$tmp"
lake exe lean-yaml value "$tmp"
lake exe lean-yaml roundtrip "$tmp"
lake exe lean-yaml emit-value "$tmp"
```

## Examples

Run examples through Lake:

```bash
lake env lean examples/config.lean
lake env lean examples/roundtrip.lean
lake env lean examples/serde.lean
```

## Library API

Import the public API:

```lean
import Yaml
```

Parsing and composing:

```lean
Yaml.parse : String -> Except Yaml.ParseError Yaml.YamlStream
Yaml.parseDocument : String -> Except Yaml.ParseError Yaml.YamlDocument
Yaml.parseByteArray : ByteArray -> Except Yaml.ParseError Yaml.YamlStream
Yaml.parseValue : String -> Yaml.Schema -> Except Yaml.ParseError Yaml.YamlValue

Yaml.compose : Yaml.YamlStream -> Except Yaml.ComposeError Yaml.YamlStream
Yaml.composeGraph : Yaml.YamlStream -> Except Yaml.ComposeError Yaml.RepresentationStream
Yaml.expandAliases : Yaml.YamlStream -> Except Yaml.ComposeError Yaml.RepresentationStream
Yaml.resolve : Yaml.Schema -> Yaml.YamlNode -> Except Yaml.SchemaError Yaml.YamlValue
```

Emitting:

```lean
Yaml.emit : Yaml.YamlStream -> Yaml.EmitOptions -> String
Yaml.emitDocument : Yaml.YamlDocument -> Yaml.EmitOptions -> String
Yaml.emitValue : Yaml.YamlValue -> Yaml.EmitOptions -> String
```

IO helpers:

```lean
Yaml.parseStream : String -> IO (Except Yaml.ParseError Yaml.YamlStream)
Yaml.emitStream : Yaml.YamlStream -> Yaml.EmitOptions -> IO String
Yaml.parseStreamFromFile : System.FilePath -> (Yaml.YamlDocument -> IO Unit) -> IO (Except Yaml.ParseError Unit)
Yaml.emitStreamToFile : System.FilePath -> Yaml.YamlStream -> Yaml.EmitOptions -> IO Unit
```

Events:

```lean
Yaml.eventsOfStream : Yaml.YamlStream -> Array Yaml.YamlEvent
Yaml.eventsOfDocument : Yaml.YamlDocument -> Array Yaml.YamlEvent
Yaml.emitEvents : Array Yaml.YamlEvent -> String
Yaml.emitStreamEvents : Yaml.YamlStream -> String
```

Serde:

```lean
Yaml.toYaml : α -> Yaml.YamlValue
Yaml.fromYaml : Yaml.YamlValue -> Except Yaml.FromYamlError α
Yaml.fromMapField : Array (Yaml.YamlValue × Yaml.YamlValue) -> String -> Except Yaml.FromYamlError α
Yaml.withTag : String -> Yaml.YamlValue -> Yaml.YamlValue
Yaml.fromTagged : String -> Yaml.YamlValue -> Except Yaml.FromYamlError α
```

## Module Layout

- `Yaml.lean`: public API re-exports and convenience functions.
- `Yaml/AST.lean`: presentation-preserving AST.
- `Yaml/Types.lean`: high-level `YamlValue`.
- `Yaml/Error.lean`: parse, compose, schema, and serde errors.
- `Yaml/Event.lean`: low-level YAML event types and AST-to-event lowering.
- `Yaml/Graph.lean`: representation graph composition and alias expansion.
- `Yaml/Parser.lean`: current parser and parse-to-value entry points.
- `Yaml/Parser/Source.lean`: source buffer and source-slice scaffolding.
- `Yaml/Parser/Token.lean`: token and YAML context scaffolding.
- `Yaml/Composer.lean`: anchor/alias validation.
- `Yaml/Schema.lean`: Failsafe, JSON, and Core schema resolution.
- `Yaml/Emitter.lean`: AST and value emission.
- `Yaml/Serde.lean`: `ToYaml`, `FromYaml`, and serde helpers.
- `Main.lean`: CLI executable.
- `Test.lean` and `YamlTest/`: structured regression test executable.
- `.github/workflows/ci.yml`: CI for build, tests, examples, CLI smoke checks,
  and YAML Test Suite harness.
- `scripts/yaml-test-suite.sh`: fetches the official YAML Test Suite and reports
  tracked classification counts.
- `suite/yaml-test-suite/classification.tsv`: pass/expected-fail/unsupported
  classification metadata.
- `examples/`: runnable examples.
- `spec.md`: long-form specification, implementation tracker, and roadmap.

## What Remains

To complete the project as specified, the main work is:

- Replace the line-oriented parser with a maintainable YAML token and production
  parser built on `lean4-parser`. This includes YAML indentation contexts,
  stream/document productions, flow/block restrictions, complex keys, directives,
  complete scalar decoding, and richer diagnostics.
- Finish round-trip fidelity by attaching comments/trivia to exact AST locations
  and teaching the emitter to preserve collection-entry comments, trailing
  trivia, original scalar layout, directives, styles, tags, anchors, order, and
  document boundaries across arbitrary supported inputs.
- Expand schema resolution to cover all YAML 1.2.2 scalar edge cases and expand
  representation-graph composition beyond the current alias-expansion subset.
- Add serde deriving macros for structures and simple inductives, then integrate
  custom tag handling into deriving.
- Broaden the official YAML Test Suite classification list and validate
  expected events/values, not just parser success or failure.
- Replace current IO wrappers with true incremental parser/emitter APIs, add
  large-file fixtures, benchmarks, throughput tracking, and only then consider
  optional FFI acceleration.
- Add Reservoir publishing metadata, API documentation comments, and richer
  tutorials once the parser surface stabilizes.

## References And Related Work

- YAML 1.2.2 specification: https://yaml.org/spec/1.2.2/
- YAML Test Suite: https://github.com/yaml/yaml-test-suite
- YAML reference site: https://yaml.org/
- `lean4-parser`: https://github.com/fgdorais/lean4-parser
- Lean package registry, Reservoir: https://reservoir.lean-lang.org/
- `libfyaml`: https://github.com/pantoniou/libfyaml
- `rapidyaml` / `ryml`: https://github.com/biojppm/rapidyaml
- `yaml-rust`: https://github.com/chyh1990/yaml-rust
- `serde_yaml`: https://github.com/dtolnay/serde-yaml
