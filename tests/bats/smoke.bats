#!/usr/bin/env bats

@test "can run tt-env --version" {
  if [[ ! -f "bin/tt-env" ]]; then
    skip "bin/tt-env not yet implemented"
  fi
  run bin/tt-env --version
  [ "$status" -eq 0 ]
}

@test "trivial assertion" {
  [ 1 -eq 1 ]
}
