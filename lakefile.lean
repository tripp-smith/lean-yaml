import Lake
open Lake DSL

package «lean-yaml» where
  srcDir := "."

require Parser from git
  "https://github.com/fgdorais/lean4-parser" @ "66271b6"

@[default_target]
lean_lib Yaml where
  roots := #[`Yaml]

lean_lib YamlTest where
  roots := #[`YamlTest]

lean_exe «lean-yaml» where
  root := `Main

lean_exe yamlTest where
  root := `Test
