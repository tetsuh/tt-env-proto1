#!/usr/bin/env bats

setup() {
  REPO_DIR="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  TT_ENV="${REPO_DIR}/bin/tt-env"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export TT_HOME="${BATS_TEST_TMPDIR}/tt-home"
  export TT_SELF_UPDATE_URL_LOG="${BATS_TEST_TMPDIR}/self-update-url.log"
  export TT_SELF_UPDATE_HEADER_LOG="${BATS_TEST_TMPDIR}/self-update-headers.log"
  export TT_SELF_UPDATE_VERSION_URL="https://example.invalid/tetsuh/tt-env-proto1/VERSION"
  unset GITHUB_TOKEN
  unset GH_TOKEN
}

make_fake_self_update_tools() {
  local fake_bin="${BATS_TEST_TMPDIR}/fake-self-update-bin"

  mkdir -p "$fake_bin"
  cat >"${fake_bin}/curl" <<'EOF'
#!/bin/sh
output=""
url=""
: >"$TT_SELF_UPDATE_HEADER_LOG"
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
      printf '%s\n' "$2" >>"$TT_SELF_UPDATE_HEADER_LOG"
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
printf '%s\n' "$url" >"$TT_SELF_UPDATE_URL_LOG"
if [ -n "${TT_FAKE_SELF_UPDATE_CURL_EXIT:-}" ]; then
  exit "$TT_FAKE_SELF_UPDATE_CURL_EXIT"
fi
case "$url" in
  *VERSION*)
    printf '%s\n' "${TT_FAKE_SELF_UPDATE_REMOTE_VERSION:-0.0.0}" >"$output"
    ;;
  *.asc)
    printf 'signature\n' >"$output"
    ;;
  *)
    printf '%s\n' "${TT_FAKE_SELF_UPDATE_BINARY:-#!/usr/bin/env bash}" >"$output"
    ;;
esac
printf '%s' "${TT_FAKE_SELF_UPDATE_HTTP_CODE:-200}"
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

@test "tt-env update --self exits cleanly when remote version is equal" {
  fake_bin="$(make_fake_self_update_tools)"
  export TT_FAKE_SELF_UPDATE_REMOTE_VERSION="0.2.0"
  export GITHUB_TOKEN="must-not-be-used"
  export GH_TOKEN="must-not-be-used"

  PATH="${fake_bin}:${PATH}" run "$TT_ENV" update --self

  [ "$status" -eq 0 ]
  [[ "$output" == *"tt-env is already up to date (0.2.0)."* ]]
  [ "$(cat "$TT_SELF_UPDATE_URL_LOG")" = "$TT_SELF_UPDATE_VERSION_URL" ]
  [ ! -s "$TT_SELF_UPDATE_HEADER_LOG" ]
  [ "$(find "${TT_HOME}/.tmp" -mindepth 1 -maxdepth 1 | wc -l)" -eq 0 ]
  [ ! -e "${TT_HOME}/manifests/last_update" ]
}

@test "tt-env update --self defaults to GitHub API with authentication when available" {
  fake_bin="$(make_fake_self_update_tools)"
  export TT_FAKE_SELF_UPDATE_REMOTE_VERSION="0.2.0"
  export GITHUB_TOKEN="self-update-token"
  unset TT_SELF_UPDATE_VERSION_URL

  PATH="${fake_bin}:${PATH}" run "$TT_ENV" update --self

  [ "$status" -eq 0 ]
  [ "$(cat "$TT_SELF_UPDATE_URL_LOG")" = "https://api.github.com/repos/tetsuh/tt-env-proto1/contents/VERSION?ref=main" ]
  [[ "$(cat "$TT_SELF_UPDATE_HEADER_LOG")" == *"Accept: application/vnd.github.raw"* ]]
  [[ "$(cat "$TT_SELF_UPDATE_HEADER_LOG")" == *"Authorization: Bearer self-update-token"* ]]
}

@test "update_self sets proceed flag when remote version is newer" {
  fake_bin="$(make_fake_self_update_tools)"
  target_file="${BATS_TEST_TMPDIR}/tt-env"
  printf '%s\n' "old" >"$target_file"
  chmod +x "$target_file"
  export TT_SELF_UPDATE_TARGET_FILE="$target_file"
  export TT_SELF_UPDATE_BINARY_URL="https://example.invalid/bin/tt-env"
  export TT_FAKE_SELF_UPDATE_BINARY='#!/usr/bin/env bash
printf "%s\n" new'
  export TT_FAKE_SELF_UPDATE_REMOTE_VERSION="0.2.1"

  PATH="${fake_bin}:${PATH}" run bash -c '
    source "$1/lib/updater.sh"
    update_self
    printf "proceed=%s remote=%s\n" "$TT_SELF_UPDATE_PROCEED" "$TT_SELF_UPDATE_REMOTE_VERSION"
  ' bash "$REPO_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Self-update available: 0.2.0 -> 0.2.1."* ]]
  [[ "$output" == *"Updated tt-env to 0.2.1."* ]]
  [[ "$output" == *"proceed=1 remote=0.2.1"* ]]
  [[ "$(cat "$target_file")" == *"new"* ]]
}

@test "update_self does not proceed when local version is newer" {
  fake_bin="$(make_fake_self_update_tools)"
  local_version_file="${BATS_TEST_TMPDIR}/VERSION"
  printf '%s\n' "0.0.2" >"$local_version_file"
  export TT_SELF_UPDATE_LOCAL_VERSION_FILE="$local_version_file"
  export TT_FAKE_SELF_UPDATE_REMOTE_VERSION="0.0.1"

  PATH="${fake_bin}:${PATH}" run bash -c '
    source "$1/lib/updater.sh"
    update_self
    printf "proceed=%s remote=%s\n" "$TT_SELF_UPDATE_PROCEED" "$TT_SELF_UPDATE_REMOTE_VERSION"
  ' bash "$REPO_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Local tt-env (0.0.2) is newer than remote (0.0.1); skipping self-update."* ]]
  [[ "$output" == *"proceed=0 remote=0.0.1"* ]]
}

@test "tt-env update --self fails clearly for malformed remote version" {
  fake_bin="$(make_fake_self_update_tools)"
  export TT_FAKE_SELF_UPDATE_REMOTE_VERSION="0.0"

  PATH="${fake_bin}:${PATH}" run "$TT_ENV" update --self

  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid semver in remote VERSION: 0.0"* ]]
}

@test "tt-env update --self fails clearly when remote VERSION cannot be fetched" {
  fake_bin="$(make_fake_self_update_tools)"
  export TT_FAKE_SELF_UPDATE_HTTP_CODE="404"

  PATH="${fake_bin}:${PATH}" run "$TT_ENV" update --self

  [ "$status" -ne 0 ]
  [[ "$output" == *"Failed to fetch remote VERSION from ${TT_SELF_UPDATE_VERSION_URL} (HTTP 404)."* ]]
}

@test "tt-env update --self rejects non-https VERSION URLs" {
  fake_bin="$(make_fake_self_update_tools)"
  export TT_SELF_UPDATE_VERSION_URL="file:///tmp/VERSION"

  PATH="${fake_bin}:${PATH}" run "$TT_ENV" update --self

  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid self-update VERSION URL: file:///tmp/VERSION"* ]]
  [ ! -e "$TT_SELF_UPDATE_URL_LOG" ]
}
