#!/usr/bin/env bats

setup() {
  REPO_DIR="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  MANIFEST_PARSER="${REPO_DIR}/lib/manifest_parser.sh"
  SECURITY_LIB="${REPO_DIR}/lib/security.sh"
}

@test "parse_env_manifest accepts allowlisted workarounds" {
  manifest_file="${BATS_TEST_TMPDIR}/allowed.env"
  printf '%s\n' 'WORKAROUNDS=(ENABLE_IOMMU)' >"$manifest_file"

  run bash -c '
    source "$1"
    parse_env_manifest "$2"
    printf "%s\n" "${TT_MANIFEST_LIST_WORKAROUNDS[0]}"
  ' bash "$MANIFEST_PARSER" "$manifest_file"

  [ "$status" -eq 0 ]
  [ "$output" = "ENABLE_IOMMU" ]
}

@test "parse_env_manifest rejects unknown workaround keys" {
  manifest_file="${BATS_TEST_TMPDIR}/unknown.env"
  printf '%s\n' 'WORKAROUNDS=(RUN_SHELL)' >"$manifest_file"

  run bash -c 'source "$1"; parse_env_manifest "$2"' bash "$MANIFEST_PARSER" "$manifest_file"

  [ "$status" -eq 1 ]
  [[ "$output" == *"Unsupported WORKAROUNDS entry: RUN_SHELL"* ]]
}

@test "parse_env_manifest rejects workaround path tokens" {
  manifest_file="${BATS_TEST_TMPDIR}/path.env"
  printf '%s\n' 'WORKAROUNDS=(../ENABLE_IOMMU)' >"$manifest_file"

  run bash -c 'source "$1"; parse_env_manifest "$2"' bash "$MANIFEST_PARSER" "$manifest_file"

  [ "$status" -eq 1 ]
  [[ "$output" == *"Unsupported WORKAROUNDS entry: ../ENABLE_IOMMU"* ]]
}

@test "parse_env_manifest rejects empty workaround entries" {
  manifest_file="${BATS_TEST_TMPDIR}/empty.env"
  printf '%s\n' 'WORKAROUNDS=("" ENABLE_IOMMU)' >"$manifest_file"

  run bash -c 'source "$1"; parse_env_manifest "$2"' bash "$MANIFEST_PARSER" "$manifest_file"

  [ "$status" -eq 1 ]
  [[ "$output" == *"Unsupported WORKAROUNDS entry: <empty>"* ]]
}

@test "allowlisted workaround maps to a lib security handler" {
  run bash -c '
    source "$1"
    handler="$(workaround_handler_for ENABLE_IOMMU)"
    declare -F "$handler" >/dev/null
    printf "%s\n" "$handler"
  ' bash "$SECURITY_LIB"

  [ "$status" -eq 0 ]
  [[ "$output" == tt_security_workaround_* ]]
}
