#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/test_helpers.bash"
  install_test_setup_common
  write_install_os_manifest "false"
  write_download_assets "downloaded"
  fake_bin="$(make_fake_curl)"
  export PATH="${fake_bin}:${PATH}"
  write_download_release_manifest
}

@test "tt-env install downloads release artifacts when PPA is disabled" {
  run "$TT_ENV" install 2024.1
  [ "$status" -eq 0 ]

  for component in tt-kmd tt-smi firmware tt-metal; do
    cmp -s "${BATS_TEST_TMPDIR}/assets/${component}" "${TT_HOME}/versions/2024.1/artifacts/${component}"
  done
}

@test "tt-env install rolls back when sha256 verification fails" {
  write_download_release_manifest "0000000000000000000000000000000000000000000000000000000000000000"

  run "$TT_ENV" install 2024.1
  [ "$status" -eq 1 ]
  [[ "$output" == *"sha256 mismatch for firmware"* ]]
  [ ! -e "${TT_HOME}/versions/2024.1" ]
  [ ! -e "${TT_HOME}/versions/.2024.1.partial" ]
}

@test "tt-env install reports missing download metadata for string components" {
  rm -f "${TT_HOME}/releases/2024.1.json"

  run "$TT_ENV" install 2024.1
  [ "$status" -eq 1 ]
  [[ "$output" == *"requires download_url and sha256 when USE_PPA=false"* ]]
  [ ! -e "${TT_HOME}/versions/2024.1" ]
}

@test "tt-env install --dry-run reports download URLs without creating the version dir" {
  run "$TT_ENV" install --dry-run 2024.1
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] Would download tt-kmd from file://${BATS_TEST_TMPDIR}/assets/tt-kmd"* ]]
  [ ! -e "${TT_HOME}/versions/2024.1" ]
}

@test "tt-env install fails clearly when curl is missing" {
  bash_env="$(make_command_absent_env curl)"

  run env BASH_ENV="$bash_env" "$TT_ENV" install 2024.1
  [ "$status" -eq 1 ]
  [[ "$output" == *"curl is required to download release artifacts"* ]]
  [ ! -e "${TT_HOME}/versions/2024.1" ]
  [ ! -e "${TT_HOME}/versions/.2024.1.partial" ]
}

@test "tt-env install removes stale partial directories before downloading" {
  mkdir -p "${TT_HOME}/versions/.2024.1.partial"
  touch "${TT_HOME}/versions/.2024.1.partial/garbage"

  run "$TT_ENV" install 2024.1
  [ "$status" -eq 0 ]
  [ ! -e "${TT_HOME}/versions/2024.1/garbage" ]
}
