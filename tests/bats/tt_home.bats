#!/usr/bin/env bats

setup() {
  TT_ENV="${BATS_TEST_DIRNAME}/../../bin/tt-env"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export TT_HOME="${BATS_TEST_TMPDIR}/tt-home"
}

assert_tt_home_layout() {
  for subdir in bin lib manifests releases versions shims; do
    [ -d "${TT_HOME}/${subdir}" ]
  done
}

@test "tt-env help creates TT_HOME directory layout" {
  run "$TT_ENV" help
  [ "$status" -eq 0 ]
  assert_tt_home_layout
}

@test "tt-env help initializes TT_HOME idempotently" {
  run "$TT_ENV" help
  [ "$status" -eq 0 ]

  run "$TT_ENV" help
  [ "$status" -eq 0 ]
  assert_tt_home_layout
}

@test "tt-env defaults TT_HOME to HOME/.tt-env" {
  unset TT_HOME

  run "$TT_ENV" list
  [ "$status" -eq 0 ]

  for subdir in bin lib manifests releases versions shims; do
    [ -d "${HOME}/.tt-env/${subdir}" ]
  done
}

@test "tt-env fails clearly when HOME and TT_HOME are unset" {
  unset HOME
  unset TT_HOME

  run "$TT_ENV" list
  [ "$status" -eq 1 ]
  [[ "$output" == *"HOME environment variable is not set."* ]]
}
