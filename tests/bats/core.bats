#!/usr/bin/env bats

setup() {
  # Load the core library
  source "${BATS_TEST_DIRNAME}/../../lib/core.sh"
}

@test "log_info prints to stdout" {
  run log_info "test message"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[INFO]"*"test message"* ]]
}

@test "log_info preserves printf metacharacters in messages" {
  run log_info 'progress 100% \n literal'
  [ "$status" -eq 0 ]
  [[ "$output" == *'progress 100% \n literal'* ]]
}

@test "log_warn prints to stderr" {
  # Redirect stdout to /dev/null; if it went to stdout, output will be empty
  run bash -c "source \"${BATS_TEST_DIRNAME}/../../lib/core.sh\" && log_warn 'warning msg' >/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[WARN]"*"warning msg"* ]]
}

@test "log_error prints to stderr" {
  # Redirect stdout to /dev/null
  run bash -c "source \"${BATS_TEST_DIRNAME}/../../lib/core.sh\" && log_error 'error msg' >/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[ERROR]"*"error msg"* ]]
}

@test "fail prints to stderr and exits 1" {
  # Redirect stdout to /dev/null
  run bash -c "source \"${BATS_TEST_DIRNAME}/../../lib/core.sh\" && fail 'fatal msg' >/dev/null"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[ERROR]"*"fatal msg"* ]]
}

@test "command_exists returns 0 for existing command" {
  run command_exists bash
  [ "$status" -eq 0 ]
}

@test "command_exists returns non-zero for missing command" {
  run command_exists definitely_not_a_command_12345
  [ "$status" -ne 0 ]
}
