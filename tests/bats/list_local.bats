#!/usr/bin/env bats

setup() {
  TT_ENV="${BATS_TEST_DIRNAME}/../../bin/tt-env"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export TT_HOME="${BATS_TEST_TMPDIR}/tt-home"
}

write_release_manifest() {
  local release="$1"

  mkdir -p "${TT_HOME}/releases"
  cat >"${TT_HOME}/releases/${release}.json" <<EOF
{
  "release": "${release}",
  "description": "Test stack ${release}",
  "components": {
    "tt-kmd": "v1.0.0",
    "tt-smi": "v1.0.0",
    "firmware": "v1.0.0",
    "tt-metal": "v1.0.0"
  }
}
EOF
}

@test "tt-env list prints none when no local releases exist" {
  run "$TT_ENV" list

  [ "$status" -eq 0 ]
  [[ "$output" == *"Releases"* ]]
  [[ "$output" == *"  (none)"* ]]
}

@test "tt-env list marks installed and available local releases" {
  write_release_manifest "2024.1"
  write_release_manifest "2024.2"
  mkdir -p "${TT_HOME}/versions/2024.1"
  touch "${TT_HOME}/versions/2024.1/.tt-env-installed"

  run "$TT_ENV" list

  [ "$status" -eq 0 ]
  [[ "$output" == *"2024.1 [installed]"* ]]
  [[ "$output" == *"2024.2 [available]"* ]]
}

@test "tt-env list does not mark unverified version dirs installed" {
  write_release_manifest "2024.1"
  mkdir -p "${TT_HOME}/versions/2024.1"

  run "$TT_ENV" list

  [ "$status" -eq 0 ]
  [[ "$output" == *"2024.1 [available]"* ]]
}

@test "tt-env list skips invalid release manifests with a warning" {
  write_release_manifest "2024.1"
  printf '{ "release": "broken" }\n' >"${TT_HOME}/releases/broken.json"

  run "$TT_ENV" list

  [ "$status" -eq 0 ]
  [[ "$output" == *"2024.1 [available]"* ]]
  [[ "$output" == *"Skipping invalid release manifest:"* ]]
  [[ "$output" == *"broken.json"* ]]
}
