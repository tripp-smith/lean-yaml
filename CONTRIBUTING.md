# Contributing

Thanks for helping improve `lean-yaml`. The project is pre-v1 and currently
prioritizes correctness, YAML 1.2.2 compatibility, stable public APIs, and clear
tests over performance work.

## Local Setup

Install Lean with `elan`, then use the pinned toolchain from `lean-toolchain`.

```bash
lake update
lake build
lake test
```

Run the broader project checks before opening a pull request:

```bash
lake build
lake test
bash scripts/yaml-test-suite.sh
lake env lean examples/config.lean
lake env lean examples/roundtrip.lean
lake env lean examples/serde.lean
```

## Development Guidelines

- Keep public APIs source-compatible unless the change is explicitly a breaking
  pre-v1 cleanup.
- Add focused tests for parser, schema, composer, emitter, serde, or CLI changes
  under `YamlTest/`.
- Update `README.md` when behavior, commands, supported YAML features, or
  limitations change.
- Classify new upstream YAML Test Suite cases in
  `suite/yaml-test-suite/classification.tsv` when parser behavior changes.
- Prefer small, reviewable changes with a clear description of the YAML behavior
  being added or fixed.

## Pull Requests

Each pull request should include:

- A summary of the user-facing or library-facing change.
- Tests or a clear explanation of why tests are not applicable.
- The commands run locally.
- Any known YAML 1.2.2 limitations that remain after the change.
