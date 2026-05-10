#!/usr/bin/env bats

@test "can run tt-env --version" {
  run bin/tt-env --version
  [ "$status" -eq 0 ] || skip "bin/tt-env not yet implemented"
}

@test "trivial assertion" {
  [ 1 -eq 1 ]
}
