#!/usr/bin/env bats

setup() {
  TT_ENV="${BATS_TEST_DIRNAME}/../../bin/tt-env"
  VERSION_FILE="${BATS_TEST_DIRNAME}/../../VERSION"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export TT_HOME="${BATS_TEST_TMPDIR}/tt-home"
}

@test "tt-env --version prints VERSION contents" {
  run "$TT_ENV" --version
  [ "$status" -eq 0 ]
  [ "$output" = "$(cat "$VERSION_FILE")" ]
}

@test "tt-env help lists supported commands" {
  run "$TT_ENV" help
  [ "$status" -eq 0 ]

  for command in install use list status update help; do
    [[ "$output" == *"$command"* ]]
  done
}

@test "tt-env --help shows usage" {
  run "$TT_ENV" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "tt-env unknown command exits non-zero with usage" {
  run "$TT_ENV" definitely-not-a-command
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown command: definitely-not-a-command"* ]]
  [[ "$output" == *"Usage:"* ]]
}

@test "tt-env subcommand stubs exit successfully" {
  for command in list update; do
    run "$TT_ENV" "$command"
    [ "$status" -eq 0 ]
    [[ "$output" == *"$command command is not implemented yet."* ]]
  done
}

@test "tt-env install requires a release argument" {
  run "$TT_ENV" install
  [ "$status" -ne 0 ]
  [[ "$output" == *"tt-env install [--dry-run] [--force] <release>"* ]]
}

@test "tt-env use requires a release argument" {
  run "$TT_ENV" use
  [ "$status" -ne 0 ]
  [[ "$output" == *"tt-env use <release>"* ]]
}
