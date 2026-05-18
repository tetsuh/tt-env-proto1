#!/usr/bin/env bats

setup() {
  TT_ENV="${BATS_TEST_DIRNAME}/../../bin/tt-env"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export TT_HOME="${BATS_TEST_TMPDIR}/tt-home"
}

@test "tt-env help install lists synopsis options examples and exit codes" {
  run "$TT_ENV" help install
  [ "$status" -eq 0 ]

  [[ "$output" == *"tt-env install - install a Tenstorrent stack release"* ]]
  [[ "$output" == *"Synopsis:"* ]]
  [[ "$output" == *"tt-env install [--dry-run] [--force] <release>"* ]]
  [[ "$output" == *"--dry-run"* ]]
  [[ "$output" == *"--force"* ]]
  [[ "$output" == *"Examples:"* ]]
  [[ "$output" == *"tt-env install --dry-run 2026.05.16"* ]]
  [[ "$output" == *"Exit codes:"* ]]
}

@test "tt-env install --help prints detailed install help" {
  run "$TT_ENV" install --help
  [ "$status" -eq 0 ]

  [[ "$output" == *"Examples:"* ]]
  [[ "$output" == *"tt-env install --force 2026.05.16"* ]]
  [[ "$output" == *"Exit codes:"* ]]
}

@test "tt-env help remove documents release removal" {
  run "$TT_ENV" help remove
  [ "$status" -eq 0 ]

  [[ "$output" == *"tt-env remove - remove an installed Tenstorrent stack release"* ]]
  [[ "$output" == *"tt-env remove <release>"* ]]
  [[ "$output" == *"release is not installed"* ]]
}

@test "tt-env help diff documents release comparison" {
  run "$TT_ENV" help diff
  [ "$status" -eq 0 ]

  [[ "$output" == *"tt-env diff - compare two stack release manifests"* ]]
  [[ "$output" == *"tt-env diff <release-a> <release-b>"* ]]
  [[ "$output" == *"tt-env diff 2026.05.16 2026.08.16"* ]]
}

@test "tt-env help update documents self-update" {
  run "$TT_ENV" help update
  [ "$status" -eq 0 ]

  [[ "$output" == *"tt-env update --self"* ]]
  [[ "$output" == *"--self"* ]]
  [[ "$output" == *"verification failure"* ]]
}

@test "tt-env help --help prints general usage" {
  run "$TT_ENV" help --help
  [ "$status" -eq 0 ]

  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"tt-env help [command]"* ]]
}

@test "tt-env help rejects unknown help topics" {
  run "$TT_ENV" help definitely-not-a-command
  [ "$status" -ne 0 ]

  [[ "$output" == *"Unknown help topic: definitely-not-a-command"* ]]
  [[ "$output" == *"Usage:"* ]]
}
