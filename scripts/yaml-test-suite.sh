#!/usr/bin/env bash
set -euo pipefail

suite_ref="${YAML_TEST_SUITE_REF:-data-2022-01-17}"
suite_dir="${YAML_TEST_SUITE_DIR:-build/yaml-test-suite}"
classification="${YAML_TEST_CLASSIFICATION:-suite/yaml-test-suite/classification.tsv}"

mkdir -p "$(dirname "$suite_dir")"

if [ ! -d "$suite_dir/.git" ]; then
  git clone --depth 1 --branch "$suite_ref" https://github.com/yaml/yaml-test-suite.git "$suite_dir"
else
  git -C "$suite_dir" fetch --depth 1 origin "$suite_ref"
  git -C "$suite_dir" checkout --detach FETCH_HEAD
fi

if [ ! -f "$classification" ]; then
  echo "missing classification file: $classification" >&2
  exit 1
fi

pass_count="$(awk -F '\t' 'NF && $1 !~ /^#/ && $2 == "pass" { n++ } END { print n + 0 }' "$classification")"
xfail_count="$(awk -F '\t' 'NF && $1 !~ /^#/ && $2 == "expectedFail" { n++ } END { print n + 0 }' "$classification")"
unsupported_count="$(awk -F '\t' 'NF && $1 !~ /^#/ && $2 == "unsupported" { n++ } END { print n + 0 }' "$classification")"

echo "YAML Test Suite fetched at $suite_dir ($suite_ref)"
echo "classification: pass=$pass_count expectedFail=$xfail_count unsupported=$unsupported_count"

failed=0
while IFS=$'\t' read -r case_id status reason; do
  case "$case_id" in
    ""|\#*) continue ;;
  esac
  case_dir="$suite_dir/$case_id"
  input="$case_dir/in.yaml"
  if [ ! -f "$input" ]; then
    echo "classified case $case_id is missing in.yaml" >&2
    failed=1
    continue
  fi
  case "$status" in
    pass)
      if ! lake exe lean-yaml parse "$input" >/dev/null; then
        echo "YAML Test Suite pass case failed: $case_id ${reason:-}" >&2
        failed=1
      fi
      ;;
    expectedFail)
      if lake exe lean-yaml parse "$input" >/dev/null; then
        echo "YAML Test Suite expected-fail case unexpectedly passed: $case_id ${reason:-}" >&2
        failed=1
      fi
      ;;
    unsupported)
      ;;
    *)
      echo "invalid classification status for $case_id: $status" >&2
      failed=1
      ;;
  esac
done < "$classification"

if [ "$failed" -ne 0 ]; then
  exit 1
fi

echo "classified YAML Test Suite cases passed"
