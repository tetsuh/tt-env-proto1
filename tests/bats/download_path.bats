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
  run "$TT_ENV" install proto-stack-2026.05.16
  [ "$status" -eq 0 ]

  for component in tt-kmd tt-smi firmware tt-metal; do
    cmp -s "${BATS_TEST_TMPDIR}/assets/${component}" "${TT_HOME}/versions/proto-stack-2026.05.16/artifacts/${component}"
  done
  [ -x "${TT_HOME}/shims/tt-smi" ]
}

@test "tt-env install rolls back when sha256 verification fails" {
  write_download_release_manifest "0000000000000000000000000000000000000000000000000000000000000000"

  run "$TT_ENV" install proto-stack-2026.05.16
  [ "$status" -eq 1 ]
  [[ "$output" == *"sha256 mismatch for firmware"* ]]
  [ ! -e "${TT_HOME}/versions/proto-stack-2026.05.16" ]
  [ ! -e "${TT_HOME}/versions/.proto-stack-2026.05.16.partial" ]
}

@test "tt-env install does not require proto1-managed artifact signatures" {
  rm -f "${BATS_TEST_TMPDIR}/assets/"*.asc

  run "$TT_ENV" install proto-stack-2026.05.16

  [ "$status" -eq 0 ]
  [ -f "${TT_HOME}/versions/proto-stack-2026.05.16/.tt-env-installed" ]
  [ ! -e "${TT_HOME}/versions/.proto-stack-2026.05.16.partial" ]
}

@test "tt-env install reports missing download metadata for string components" {
  rm -f "${TT_HOME}/releases/proto-stack-2026.05.16.json"

  run "$TT_ENV" install proto-stack-2026.05.16
  [ "$status" -eq 1 ]
  [[ "$output" == *"requires download_url and sha256 when system package installation is disabled"* ]]
  [ ! -e "${TT_HOME}/versions/proto-stack-2026.05.16" ]
}

@test "tt-env install --dry-run reports download URLs without creating the version dir" {
  run "$TT_ENV" install --dry-run proto-stack-2026.05.16
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] Would download tt-kmd from file://${BATS_TEST_TMPDIR}/assets/tt-kmd"* ]]
  [[ "$output" != *"signature"* ]]
  [ ! -e "${TT_HOME}/versions/proto-stack-2026.05.16" ]
}

@test "tt-env install fails clearly when curl is missing" {
  bash_env="$(make_command_absent_env curl)"

  run env BASH_ENV="$bash_env" "$TT_ENV" install proto-stack-2026.05.16
  [ "$status" -eq 1 ]
  [[ "$output" == *"curl is required to download release artifacts"* ]]
  [ ! -e "${TT_HOME}/versions/proto-stack-2026.05.16" ]
  [ ! -e "${TT_HOME}/versions/.proto-stack-2026.05.16.partial" ]
}

@test "tt-env install removes stale partial directories before downloading" {
  mkdir -p "${TT_HOME}/versions/.proto-stack-2026.05.16.partial"
  touch "${TT_HOME}/versions/.proto-stack-2026.05.16.partial/garbage"

  run "$TT_ENV" install proto-stack-2026.05.16
  [ "$status" -eq 0 ]
  [ ! -e "${TT_HOME}/versions/proto-stack-2026.05.16/garbage" ]
}
