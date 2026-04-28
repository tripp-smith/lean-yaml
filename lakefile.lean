import Lake
open Lake DSL

package «lean-yaml» where
  srcDir := "."
  version := v!"0.1.0"
  description := "A Lean 4 YAML library aimed at YAML 1.2.2 compliance, round-trippable syntax trees, schemas, serde, and CLI tooling."
  keywords := #["yaml", "parser", "serialization", "configuration", "cli"]
  license := "Apache-2.0"
  readmeFile := "README.md"

require Parser from git
  "https://github.com/fgdorais/lean4-parser" @ "66271b6"

@[default_target]
lean_lib Yaml where
  roots := #[`Yaml]

lean_lib YamlTest where
  roots := #[`YamlTest]

lean_exe «lean-yaml» where
  root := `Main

@[test_driver]
lean_exe yamlTest where
  root := `Test
