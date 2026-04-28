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

lake build lean-yaml >/dev/null
lean_yaml_exe="${LEAN_YAML_EXE:-.lake/build/bin/lean-yaml}"

if [ ! -f "$classification" ]; then
  echo "missing classification file: $classification" >&2
  exit 1
fi

all_cases="$(mktemp)"
classified_cases="$(mktemp)"
duplicate_cases="$(mktemp)"
invalid_refs="$(mktemp)"
unclassified_cases="$(mktemp)"
trap 'rm -f "$all_cases" "$classified_cases" "$duplicate_cases" "$invalid_refs" "$unclassified_cases"' EXIT

find "$suite_dir" -name in.yaml \
  | sed "s#^$suite_dir/##; s#/in.yaml\$##" \
  | awk -F/ '$1 ~ /^[A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9]$/' \
  | sort > "$all_cases"
awk -F '\t' 'NF && $1 !~ /^#/ { print $1 }' "$classification" | sort > "$classified_cases"
awk -F '\t' 'NF && $1 !~ /^#/ { seen[$1]++ } END { for (case_id in seen) if (seen[case_id] > 1) print case_id }' "$classification" | sort > "$duplicate_cases"
comm -23 "$classified_cases" "$all_cases" > "$invalid_refs"
comm -23 "$all_cases" "$classified_cases" > "$unclassified_cases"

if [ -s "$duplicate_cases" ]; then
  echo "duplicate YAML Test Suite classification entries:" >&2
  cat "$duplicate_cases" >&2
  exit 1
fi

if [ -s "$invalid_refs" ]; then
  echo "classification references missing upstream cases:" >&2
  cat "$invalid_refs" >&2
  exit 1
fi

if [ -s "$unclassified_cases" ]; then
  echo "unclassified YAML Test Suite cases:" >&2
  cat "$unclassified_cases" >&2
  exit 1
fi

pass_count="$(awk -F '\t' 'NF && $1 !~ /^#/ && $2 == "pass" { n++ } END { print n + 0 }' "$classification")"
xfail_count="$(awk -F '\t' 'NF && $1 !~ /^#/ && $2 == "expectedFail" { n++ } END { print n + 0 }' "$classification")"
unsupported_count="$(awk -F '\t' 'NF && $1 !~ /^#/ && $2 == "unsupported" { n++ } END { print n + 0 }' "$classification")"
total_count="$(wc -l < "$all_cases" | tr -d ' ')"
classified_count="$(wc -l < "$classified_cases" | tr -d ' ')"

echo "YAML Test Suite fetched at $suite_dir ($suite_ref)"
echo "classification: total=$total_count classified=$classified_count pass=$pass_count expectedFail=$xfail_count unsupported=$unsupported_count"

normalize_events() {
  sed '/^[[:space:]]*$/d' "$1"
}

json_equal() {
  ruby -rjson -e 'exit(JSON.parse(File.read(ARGV[0])) == JSON.parse(File.read(ARGV[1])) ? 0 : 1)' "$1" "$2"
}

check_valid_case() {
  local input="$1"
  local expected_events="$2"
  local expected_json="$3"
  local case_id="$4"
  local reason="${5:-}"
  local actual_events=""
  local expected_events_normalized=""
  local actual_json=""

  if ! "$lean_yaml_exe" parse "$input" >/dev/null; then
    echo "YAML Test Suite pass case failed: $case_id $reason" >&2
    return 1
  fi
  if [ -f "$expected_events" ]; then
    actual_events="$(mktemp)"
    expected_events_normalized="$(mktemp)"
    if "$lean_yaml_exe" suite-events "$input" > "$actual_events"; then
      normalize_events "$expected_events" > "$expected_events_normalized"
      if ! diff -u "$expected_events_normalized" "$actual_events" >/dev/null; then
        echo "YAML Test Suite event mismatch: $case_id $reason" >&2
        diff -u "$expected_events_normalized" "$actual_events" >&2 || true
        rm -f "$actual_events" "$expected_events_normalized"
        return 1
      fi
    else
      echo "YAML Test Suite event emission failed: $case_id $reason" >&2
      rm -f "$actual_events" "$expected_events_normalized"
      return 1
    fi
    rm -f "$actual_events" "$expected_events_normalized"
  fi
  if [ -f "$expected_json" ]; then
    actual_json="$(mktemp)"
    if "$lean_yaml_exe" json "$input" > "$actual_json"; then
      if ! json_equal "$expected_json" "$actual_json"; then
        echo "YAML Test Suite JSON mismatch: $case_id $reason" >&2
        echo "expected: $expected_json" >&2
        echo "actual: $actual_json" >&2
        rm -f "$actual_json"
        return 1
      fi
    else
      echo "YAML Test Suite JSON emission failed: $case_id $reason" >&2
      rm -f "$actual_json"
      return 1
    fi
    rm -f "$actual_json"
  fi
}

check_error_case() {
  local input="$1"
  if "$lean_yaml_exe" parse "$input" >/dev/null 2>&1; then
    return 1
  fi
}

failed=0
while IFS=$'\t' read -r case_id status reason; do
  case "$case_id" in
    ""|\#*) continue ;;
  esac
  case_dir="$suite_dir/$case_id"
  input="$case_dir/in.yaml"
  is_error=0
  if [ -f "$case_dir/error" ]; then
    is_error=1
  fi
  if [ ! -f "$input" ]; then
    echo "classified case $case_id is missing in.yaml" >&2
    failed=1
    continue
  fi
  expected_events="$case_dir/test.event"
  expected_json="$case_dir/in.json"
  case "$status" in
    pass)
      if [ "$is_error" -eq 1 ]; then
        if ! check_error_case "$input"; then
          echo "YAML Test Suite invalid pass case was accepted: $case_id ${reason:-}" >&2
          failed=1
        fi
      else
        if ! check_valid_case "$input" "$expected_events" "$expected_json" "$case_id" "${reason:-}"; then
          failed=1
        fi
      fi
      ;;
    expectedFail)
      if [ "$is_error" -eq 1 ]; then
        if check_error_case "$input"; then
          echo "YAML Test Suite expected-fail invalid case now fails as expected: $case_id ${reason:-}" >&2
          failed=1
        fi
      else
        if check_valid_case "$input" "$expected_events" "$expected_json" "$case_id" "${reason:-}" >/dev/null 2>&1; then
          echo "YAML Test Suite expected-fail case unexpectedly passed: $case_id ${reason:-}" >&2
          failed=1
        fi
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
