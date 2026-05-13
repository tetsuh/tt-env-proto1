#!/usr/bin/env bats

setup() {
  REPO_DIR="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  TT_ENV="${REPO_DIR}/bin/tt-env"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export TT_HOME="${BATS_TEST_TMPDIR}/tt-home"
  export TT_SELF_UPDATE_VERSION_URL="https://example.invalid/VERSION"
  export TT_SELF_UPDATE_BINARY_URL="https://example.invalid/bin/tt-env"
  unset TT_SELF_UPDATE_SIGNATURE_URL
  unset GITHUB_TOKEN
  unset GH_TOKEN
}

make_self_update_target() {
  local target_file="${BATS_TEST_TMPDIR}/install/bin/tt-env"

  mkdir -p "$(dirname "$target_file")"
  cat >"$target_file" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' old-version
EOF
  chmod +x "$target_file"
  printf '%s\n' "$target_file"
}

make_fake_replace_tools() {
  local fake_bin="${BATS_TEST_TMPDIR}/fake-self-update-replace-bin"

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
    printf '%s\n' "0.1.1" >"$output"
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
  if [[ -n "${TT_FAKE_GPG_VERIFY_EXIT:-}" && "${TT_FAKE_GPG_VERIFY_EXIT}" -ne 0 ]]; then
    printf '[GNUPG:] BADSIG C55FEB196FB67D83F63FE18CBEF418235C011DF8 test\n'
    exit "$TT_FAKE_GPG_VERIFY_EXIT"
  fi
  printf '[GNUPG:] VALIDSIG C55FEB196FB67D83F63FE18CBEF418235C011DF8 0 0 0 0 0 0 0 0 C55FEB196FB67D83F63FE18CBEF418235C011DF8\n'
  exit 0
fi
exit 0
EOF
  chmod +x "${fake_bin}/curl" "${fake_bin}/gpg"
  printf '%s\n' "$fake_bin"
}

@test "tt-env update --self atomically replaces after a good signature" {
  fake_bin="$(make_fake_replace_tools)"
  target_file="$(make_self_update_target)"
  export TT_SELF_UPDATE_TARGET_FILE="$target_file"

  PATH="${fake_bin}:${PATH}" run "$TT_ENV" update --self

  [ "$status" -eq 0 ]
  [[ "$output" == *"Updated tt-env to 0.1.1."* ]]
  [ "$("$target_file")" = "new-version" ]
  [ -x "$target_file" ]
  [ "$(find "$(dirname "$target_file")" -name '.tt-env-self-update.*' | wc -l)" -eq 0 ]
}

@test "tt-env update --self leaves target unchanged after a bad signature" {
  fake_bin="$(make_fake_replace_tools)"
  target_file="$(make_self_update_target)"
  export TT_SELF_UPDATE_TARGET_FILE="$target_file"
  export TT_FAKE_GPG_VERIFY_EXIT=1

  PATH="${fake_bin}:${PATH}" run "$TT_ENV" update --self

  [ "$status" -ne 0 ]
  [[ "$output" == *"GPG signature verification failed"* ]]
  [ "$("$target_file")" = "old-version" ]
  [ "$(find "$(dirname "$target_file")" -name '.tt-env-self-update.*' | wc -l)" -eq 0 ]
}
