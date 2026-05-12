#!/usr/bin/env bats

setup() {
  REPO_DIR="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  LINT_SH="${REPO_DIR}/scripts/lint.sh"
}

@test "lint accepts manifest_parser without source or dot commands" {
  run env TT_LINT_NO_SOURCE_ONLY=1 bash "$LINT_SH"
  [ "$status" -eq 0 ]
}

@test "lint rejects source inside manifest_parser" {
  manifest_parser="${BATS_TEST_TMPDIR}/manifest_parser.sh"
  cp "${REPO_DIR}/lib/manifest_parser.sh" "$manifest_parser"
  printf '\nsource ./evil.sh\n' >>"$manifest_parser"

  run env TT_LINT_NO_SOURCE_ONLY=1 TT_LINT_MANIFEST_PARSER_FILE="$manifest_parser" bash "$LINT_SH"

  [ "$status" -eq 1 ]
  [[ "$output" == *"must not invoke source or ."* ]]
  [[ "$output" == *"source ./evil.sh"* ]]
}

@test "lint rejects dot command inside manifest_parser" {
  manifest_parser="${BATS_TEST_TMPDIR}/manifest_parser.sh"
  cp "${REPO_DIR}/lib/manifest_parser.sh" "$manifest_parser"
  printf '\n. ./evil.sh\n' >>"$manifest_parser"

  run env TT_LINT_NO_SOURCE_ONLY=1 TT_LINT_MANIFEST_PARSER_FILE="$manifest_parser" bash "$LINT_SH"

  [ "$status" -eq 1 ]
  [[ "$output" == *"must not invoke source or ."* ]]
  [[ "$output" == *". ./evil.sh"* ]]
}
