#!/usr/bin/env bats

setup() {
  REPO_DIR="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  TT_ENV="${REPO_DIR}/bin/tt-env"
  helper_pid=""
  export HOME="${BATS_TEST_TMPDIR}/home"
  export TT_HOME="${BATS_TEST_TMPDIR}/tt-home"
  export TT_SELF_UPDATE_VERSION_URL="https://example.invalid/VERSION"
  export TT_SELF_UPDATE_BINARY_URL="https://example.invalid/bin/tt-env"
  unset TT_SELF_UPDATE_SIGNATURE_URL
  unset GITHUB_TOKEN
  unset GH_TOKEN
}

teardown() {
  if [[ -n "${helper_pid:-}" ]]; then
    kill "$helper_pid" 2>/dev/null || true
    wait "$helper_pid" 2>/dev/null || true
  fi
}

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

make_running_target() {
  local target_file="${BATS_TEST_TMPDIR}/install/bin/tt-env"

  mkdir -p "$(dirname "$target_file")"
  cat >"$target_file" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' old-started >>"$TT_RUNNING_HELPER_LOG"
: >"$TT_RUNNING_HELPER_STARTED"
while [[ ! -f "$TT_RUNNING_HELPER_CONTINUE" ]]; do
  sleep 0.05
done
printf '%s\n' old-finished >>"$TT_RUNNING_HELPER_LOG"
EOF
  chmod +x "$target_file"
  printf '%s\n' "$target_file"
}

make_fake_running_tools() {
  local fake_bin="${BATS_TEST_TMPDIR}/fake-self-update-running-bin"

  mkdir -p "$fake_bin"
  cat >"${fake_bin}/curl" <<'EOF'
#!/bin/sh
output=""
url=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output)
      output="$2"
      shift 2
      ;;
    --write-out)
      shift 2
      ;;
    --header)
      shift 2
      ;;
    --location|--silent|--show-error)
      shift
      ;;
    *)
      url="$1"
      shift
      ;;
  esac
done
case "$url" in
  *VERSION)
    printf '%s\n' "0.0.1" >"$output"
    ;;
  *.asc)
    printf '%s\n' "signature" >"$output"
    ;;
  *)
    cat >"$output" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\n' new-version
SCRIPT
    ;;
esac
printf '200'
EOF
  cat >"${fake_bin}/gpg" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"--with-colons"* && "$*" == *"--fingerprint"* ]]; then
  printf 'pub:::::::::\n'
  printf 'fpr:::::::::C55FEB196FB67D83F63FE18CBEF418235C011DF8:\n'
  exit 0
fi
if [[ "$*" == *"--import"* ]]; then
  exit 0
fi
if [[ "$*" == *"--verify"* ]]; then
  printf '[GNUPG:] VALIDSIG C55FEB196FB67D83F63FE18CBEF418235C011DF8 0 0 0 0 0 0 0 0 C55FEB196FB67D83F63FE18CBEF418235C011DF8\n'
  exit 0
fi
exit 0
EOF
  chmod +x "${fake_bin}/curl" "${fake_bin}/gpg"
  printf '%s\n' "$fake_bin"
}

@test "running helper exits 0 after self-update replaces its script" {
  fake_bin="$(make_fake_running_tools)"
  target_file="$(make_running_target)"
  export TT_SELF_UPDATE_TARGET_FILE="$target_file"
  export TT_RUNNING_HELPER_LOG="${BATS_TEST_TMPDIR}/running-helper.log"
  export TT_RUNNING_HELPER_STARTED="${BATS_TEST_TMPDIR}/running-helper.started"
  export TT_RUNNING_HELPER_CONTINUE="${BATS_TEST_TMPDIR}/running-helper.continue"
  before_hash="$(hash_file "$target_file")"

  "$target_file" &
  helper_pid="$!"
  for _ in {1..100}; do
    [[ -f "$TT_RUNNING_HELPER_STARTED" ]] && break
    sleep 0.05
  done
  [ -f "$TT_RUNNING_HELPER_STARTED" ]

  PATH="${fake_bin}:${PATH}" run "$TT_ENV" update --self

  [ "$status" -eq 0 ]
  [[ "$output" == *"Updated tt-env to 0.0.1."* ]]
  after_hash="$(hash_file "$target_file")"
  [ "$before_hash" != "$after_hash" ]
  [ "$("$target_file")" = "new-version" ]

  : >"$TT_RUNNING_HELPER_CONTINUE"
  wait "$helper_pid"
  helper_pid=""
  run cat "$TT_RUNNING_HELPER_LOG"
  [ "$status" -eq 0 ]
  [ "$output" = $'old-started\nold-finished' ]
  [ "$(find "$(dirname "$target_file")" -name '.tt-env-self-update.*' | wc -l)" -eq 0 ]
}
