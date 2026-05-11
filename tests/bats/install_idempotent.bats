#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/test_helpers.bash"
  install_test_setup_common
}

write_download_manifest() {
  write_install_os_manifest "false"
  write_download_assets "idempotent"
  write_download_release_manifest
}

@test "second install is a no-op and does not rerun download path" {
  fake_bin="$(make_fake_curl)"
  write_download_manifest

  run env PATH="${fake_bin}:${PATH}" "$TT_ENV" install 2024.1
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$TT_CURL_LOG")" -eq 4 ]

  run env PATH="${fake_bin}:${PATH}" "$TT_ENV" install 2024.1
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
  [ "$(wc -l <"$TT_CURL_LOG")" -eq 4 ]
}

@test "tt-env install --force reruns apt path from scratch" {
  fake_bin="$(make_fake_sudo)"
  write_install_os_manifest "true"

  run env PATH="${fake_bin}:${PATH}" "$TT_ENV" install 2024.1
  [ "$status" -eq 0 ]

  run env PATH="${fake_bin}:${PATH}" "$TT_ENV" install 2024.1
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]

  run env PATH="${fake_bin}:${PATH}" "$TT_ENV" install --force 2024.1
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$TT_APT_LOG")" -eq 6 ]
}

@test "tt-env install --force reruns download path from scratch" {
  fake_bin="$(make_fake_curl)"
  write_download_manifest

  run env PATH="${fake_bin}:${PATH}" "$TT_ENV" install 2024.1
  [ "$status" -eq 0 ]

  run env PATH="${fake_bin}:${PATH}" "$TT_ENV" install 2024.1
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]

  run env PATH="${fake_bin}:${PATH}" "$TT_ENV" install --force 2024.1
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$TT_CURL_LOG")" -eq 8 ]
}
