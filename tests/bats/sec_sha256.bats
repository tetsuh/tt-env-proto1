#!/usr/bin/env bats

setup() {
  REPO_DIR="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  SECURITY_LIB="${REPO_DIR}/lib/security.sh"
  payload="${BATS_TEST_TMPDIR}/payload"
  printf 'trusted payload\n' >"$payload"
}

sha256_for() {
  sha256sum "$1" | awk '{ print $1 }'
}

@test "verify_sha256 accepts matching checksum" {
  expected="$(sha256_for "$payload")"

  run bash -c 'source "$1"; verify_sha256 "$2" "$3"' _ "$SECURITY_LIB" "$payload" "$expected"
  [ "$status" -eq 0 ]
}

@test "verify_sha256 accepts uppercase checksum" {
  expected="$(sha256_for "$payload" | tr '[:lower:]' '[:upper:]')"

  run bash -c 'source "$1"; verify_sha256 "$2" "$3"' _ "$SECURITY_LIB" "$payload" "$expected"
  [ "$status" -eq 0 ]
}

@test "verify_sha256 fails clearly on mismatch" {
  expected="0000000000000000000000000000000000000000000000000000000000000000"
  actual="$(sha256_for "$payload")"

  run bash -c 'source "$1"; verify_sha256 "$2" "$3"' _ "$SECURITY_LIB" "$payload" "$expected"
  [ "$status" -eq 1 ]
  [[ "$output" == *"sha256 mismatch for ${payload}"* ]]
  [[ "$output" == *"expected ${expected}, got ${actual}"* ]]
}

@test "calculate_sha256 fails clearly when file is missing" {
  missing="${BATS_TEST_TMPDIR}/missing"

  run bash -c 'source "$1"; calculate_sha256 "$2"' _ "$SECURITY_LIB" "$missing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Cannot calculate sha256; file not found: ${missing}"* ]]
}
