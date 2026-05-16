#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/test_helpers.bash"
  install_test_setup_common
  write_install_os_manifest "false"
  write_download_assets "asset"
  fake_bin="$(make_fake_curl)"
  export PATH="${fake_bin}:${PATH}"
  write_download_release_manifest
}

@test "tt-env install creates a per-release version directory" {
  run "$TT_ENV" install proto-stack-2026.05.16
  [ "$status" -eq 0 ]
  [ -d "${TT_HOME}/versions/proto-stack-2026.05.16" ]
  [ -f "${TT_HOME}/versions/proto-stack-2026.05.16/.tt-env-installed" ]
  [[ "$output" == *"Installed release proto-stack-2026.05.16"* ]]
}

@test "tt-env install is a no-op when release is already installed" {
  run "$TT_ENV" install proto-stack-2026.05.16
  [ "$status" -eq 0 ]

  run "$TT_ENV" install proto-stack-2026.05.16
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
}

@test "tt-env install --force re-creates the version directory" {
  run "$TT_ENV" install proto-stack-2026.05.16
  [ "$status" -eq 0 ]

  touch "${TT_HOME}/versions/proto-stack-2026.05.16/sentinel"

  run "$TT_ENV" install --force proto-stack-2026.05.16
  [ "$status" -eq 0 ]
  [ -d "${TT_HOME}/versions/proto-stack-2026.05.16" ]
  [ -f "${TT_HOME}/versions/proto-stack-2026.05.16/.tt-env-installed" ]
  [ ! -d "${TT_HOME}/versions/proto-stack-2026.05.16/.proto-stack-2026.05.16.partial" ]
  [ ! -e "${TT_HOME}/versions/proto-stack-2026.05.16/sentinel" ]
  [[ "$output" == *"Removing existing version directory"* ]]
}

@test "tt-env install --dry-run prints planned actions without creating the directory" {
  run "$TT_ENV" install --dry-run proto-stack-2026.05.16
  [ "$status" -eq 0 ]
  [ ! -e "${TT_HOME}/versions/proto-stack-2026.05.16" ]
  [[ "$output" == *"[dry-run] Would create version directory"* ]]
}

@test "tt-env install rejects unsafe release names" {
  run "$TT_ENV" install ..
  [ "$status" -eq 1 ]
  [[ "$output" == *"Invalid release name: .."* ]]

  [ ! -e "${TT_HOME}/versions" ] || [ -z "$(find "${TT_HOME}/versions" -mindepth 1 -print -quit)" ]
}

@test "tt-env install fails when the release manifest is missing" {
  run "$TT_ENV" install 2099.9
  [ "$status" -eq 1 ]
  [[ "$output" == *"Release manifest not found for 2099.9"* ]]
  [ ! -e "${TT_HOME}/versions/2099.9" ]
}

@test "tt-env install refuses an unmarked existing version directory without --force" {
  mkdir -p "${TT_HOME}/versions/proto-stack-2026.05.16"

  run "$TT_ENV" install proto-stack-2026.05.16
  [ "$status" -eq 1 ]
  [[ "$output" == *"Version directory exists but is not marked installed"* ]]
}
