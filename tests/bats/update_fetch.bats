#!/usr/bin/env bats

setup() {
  TT_ENV="${BATS_TEST_DIRNAME}/../../bin/tt-env"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export TT_HOME="${BATS_TEST_TMPDIR}/tt-home"
  export TT_FAKE_CURL_HEADER_LOG="${BATS_TEST_TMPDIR}/curl-headers.log"
  export TT_FAKE_CURL_URL_LOG="${BATS_TEST_TMPDIR}/curl-url.log"
  export TT_UPDATE_NOW_EPOCH=1700000000
  unset GITHUB_TOKEN
  unset GH_TOKEN
}

write_release_manifest() {
  local dir="$1"
  local release="$2"

  mkdir -p "${dir}/releases"
  cat >"${dir}/releases/${release}.json" <<EOF
{
  "release": "${release}",
  "description": "Test stack ${release}",
  "components": {
    "tt-kmd": "v1.0.0",
    "tt-smi": "v1.0.0",
    "firmware": "v1.0.0",
    "tt-metal": "v1.0.0"
  }
}
EOF
}

write_manifest_signatures() {
  local dir="$1"

  for manifest_file in "${dir}/releases/"*.json "${dir}/manifests/"*.env; do
    [ -f "$manifest_file" ] || continue
    printf 'signature:%s\n' "$(basename "$manifest_file")" >"${manifest_file}.asc"
  done
}

make_manifest_archive() {
  local archive_path="${BATS_TEST_TMPDIR}/manifests.tar.gz"
  local source_root="${BATS_TEST_TMPDIR}/archive-source"
  local repo_root="${source_root}/tt-env-manifests-proto1-main"

  rm -rf "$source_root"
  mkdir -p "${repo_root}/manifests"
  write_release_manifest "$repo_root" "2024.2"
  printf 'PKG_MANAGER="apt"\n' >"${repo_root}/manifests/ubuntu-22.04.env"
  tar -czf "$archive_path" -C "$source_root" "tt-env-manifests-proto1-main"
  printf '%s\n' "$archive_path"
}

make_manifest_archive_without_signature() {
  local archive_path="${BATS_TEST_TMPDIR}/unsigned-manifests.tar.gz"
  local source_root="${BATS_TEST_TMPDIR}/archive-source-unsigned"
  local repo_root="${source_root}/tt-env-manifests-proto1-main"

  rm -rf "$source_root"
  mkdir -p "${repo_root}/manifests"
  write_release_manifest "$repo_root" "2024.2"
  printf 'PKG_MANAGER="apt"\n' >"${repo_root}/manifests/ubuntu-22.04.env"
  tar -czf "$archive_path" -C "$source_root" "tt-env-manifests-proto1-main"
  printf '%s\n' "$archive_path"
}

make_manifest_archive_without_manifests() {
  local archive_path="${BATS_TEST_TMPDIR}/missing-manifests.tar.gz"
  local source_root="${BATS_TEST_TMPDIR}/archive-source-missing"
  local repo_root="${source_root}/tt-env-manifests-proto1-main"

  rm -rf "$source_root"
  write_release_manifest "$repo_root" "2024.2"
  tar -czf "$archive_path" -C "$source_root" "tt-env-manifests-proto1-main"
  printf '%s\n' "$archive_path"
}

make_fake_update_tools() {
  local fake_bin="${BATS_TEST_TMPDIR}/fake-update-bin"

  mkdir -p "$fake_bin"
  cat >"${fake_bin}/curl" <<'EOF'
#!/bin/sh
output=""
header_arg=""
url=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output)
      output="$2"
      shift 2
      ;;
    --header)
      header_arg="$2"
      shift 2
      ;;
    --write-out)
      shift 2
      ;;
    --retry)
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
header_file="${header_arg#@}"
if [ -n "$TT_FAKE_CURL_HEADER_LOG" ] && [ -f "$header_file" ]; then
  cp "$header_file" "$TT_FAKE_CURL_HEADER_LOG"
fi
if [ -n "$TT_FAKE_CURL_URL_LOG" ]; then
  printf '%s\n' "$url" >"$TT_FAKE_CURL_URL_LOG"
fi
if [ -n "${TT_FAKE_CURL_EXIT:-}" ]; then
  exit "$TT_FAKE_CURL_EXIT"
fi
if [ -n "${TT_FAKE_ARCHIVE:-}" ]; then
  cp "$TT_FAKE_ARCHIVE" "$output"
else
  : >"$output"
fi
printf '%s' "${TT_FAKE_CURL_HTTP_CODE:-200}"
EOF
  cat >"${fake_bin}/gh" <<'EOF'
#!/bin/sh
if [ "$1" = "auth" ] && [ "$2" = "token" ] && [ -n "${TT_FAKE_GH_TOKEN:-}" ]; then
  printf '%s\n' "$TT_FAKE_GH_TOKEN"
  exit 0
fi
exit 1
EOF
  chmod +x "${fake_bin}/curl" "${fake_bin}/gh"
  printf '%s\n' "$fake_bin"
}

@test "tt-env update fetches manifests with GITHUB_TOKEN" {
  fake_bin="$(make_fake_update_tools)"
  export TT_FAKE_ARCHIVE
  TT_FAKE_ARCHIVE="$(make_manifest_archive)"
  export GITHUB_TOKEN="env-token"
  export GH_TOKEN="gh-env-token"
  mkdir -p "${TT_HOME}/releases" "${TT_HOME}/manifests"
  printf 'old\n' >"${TT_HOME}/releases/old.json"
  printf 'old\n' >"${TT_HOME}/manifests/old.env"

  PATH="${fake_bin}:${PATH}" run "$TT_ENV" update

  [ "$status" -eq 0 ]
  [ -f "${TT_HOME}/releases/2024.2.json" ]
  [ -f "${TT_HOME}/manifests/ubuntu-22.04.env" ]
  [ ! -e "${TT_HOME}/releases/old.json" ]
  [ ! -e "${TT_HOME}/manifests/old.env" ]
  [ "$(cat "${TT_HOME}/manifests/last_update")" = "1700000000" ]
  [[ "$(cat "$TT_FAKE_CURL_HEADER_LOG")" == *"Authorization: Bearer env-token"* ]]
  [[ "$(cat "$TT_FAKE_CURL_URL_LOG")" == *"tetsuh/tt-env-manifests-proto1/tarball/main"* ]]
}

@test "tt-env update uses GH_TOKEN without gh auth" {
  fake_bin="$(make_fake_update_tools)"
  export TT_FAKE_ARCHIVE
  TT_FAKE_ARCHIVE="$(make_manifest_archive)"
  export GH_TOKEN="gh-env-token"

  PATH="${fake_bin}:${PATH}" run "$TT_ENV" update

  [ "$status" -eq 0 ]
  [[ "$(cat "$TT_FAKE_CURL_HEADER_LOG")" == *"Authorization: Bearer gh-env-token"* ]]
}

@test "tt-env update falls back to gh auth token" {
  fake_bin="$(make_fake_update_tools)"
  export TT_FAKE_ARCHIVE
  TT_FAKE_ARCHIVE="$(make_manifest_archive)"
  export TT_FAKE_GH_TOKEN="gh-token"

  PATH="${fake_bin}:${PATH}" run "$TT_ENV" update

  [ "$status" -eq 0 ]
  [[ "$(cat "$TT_FAKE_CURL_HEADER_LOG")" == *"Authorization: Bearer gh-token"* ]]
}

@test "tt-env update fails clearly without authentication" {
  fake_bin="$(make_fake_update_tools)"

  PATH="${fake_bin}:${PATH}" run "$TT_ENV" update

  [ "$status" -ne 0 ]
  [[ "$output" == *"Authentication is required to update manifests"* ]]
  [[ "$output" == *"Set GITHUB_TOKEN or run: gh auth login"* ]]
}

@test "tt-env update reports rejected credentials" {
  fake_bin="$(make_fake_update_tools)"
  export GITHUB_TOKEN="bad-token"
  export TT_FAKE_CURL_HTTP_CODE=403

  PATH="${fake_bin}:${PATH}" run "$TT_ENV" update

  [ "$status" -ne 0 ]
  [[ "$output" == *"Authentication failed while fetching manifests"* ]]
  [[ "$output" == *"Check GITHUB_TOKEN or run: gh auth login"* ]]
}

@test "tt-env update preserves existing manifests when archive is incomplete" {
  fake_bin="$(make_fake_update_tools)"
  export TT_FAKE_ARCHIVE
  TT_FAKE_ARCHIVE="$(make_manifest_archive_without_manifests)"
  export GITHUB_TOKEN="env-token"
  mkdir -p "${TT_HOME}/releases" "${TT_HOME}/manifests"
  printf 'old release\n' >"${TT_HOME}/releases/old.json"
  printf 'old manifest\n' >"${TT_HOME}/manifests/old.env"

  PATH="${fake_bin}:${PATH}" run "$TT_ENV" update

  [ "$status" -ne 0 ]
  [[ "$output" == *"Manifest archive is missing manifests/"* ]]
  [ "$(cat "${TT_HOME}/releases/old.json")" = "old release" ]
  [ "$(cat "${TT_HOME}/manifests/old.env")" = "old manifest" ]
}

@test "tt-env update accepts manifest archives without proto1-managed signatures" {
  fake_bin="$(make_fake_update_tools)"
  export TT_FAKE_ARCHIVE
  TT_FAKE_ARCHIVE="$(make_manifest_archive_without_signature)"
  export GITHUB_TOKEN="env-token"
  mkdir -p "${TT_HOME}/releases" "${TT_HOME}/manifests"
  printf 'old release\n' >"${TT_HOME}/releases/old.json"
  printf 'old manifest\n' >"${TT_HOME}/manifests/old.env"

  PATH="${fake_bin}:${PATH}" run "$TT_ENV" update

  [ "$status" -eq 0 ]
  [ -f "${TT_HOME}/releases/2024.2.json" ]
  [ -f "${TT_HOME}/manifests/ubuntu-22.04.env" ]
  [ ! -e "${TT_HOME}/releases/2024.2.json.asc" ]
}

@test "tt-env update ignores legacy sidecar signatures in manifest archives" {
  fake_bin="$(make_fake_update_tools)"
  export TT_FAKE_ARCHIVE
  archive_path="${BATS_TEST_TMPDIR}/signed-manifests.tar.gz"
  source_root="${BATS_TEST_TMPDIR}/archive-source-signed"
  repo_root="${source_root}/tt-env-manifests-proto1-main"
  rm -rf "$source_root"
  mkdir -p "${repo_root}/manifests"
  write_release_manifest "$repo_root" "2024.2"
  printf 'PKG_MANAGER="apt"\n' >"${repo_root}/manifests/ubuntu-22.04.env"
  write_manifest_signatures "$repo_root"
  tar -czf "$archive_path" -C "$source_root" "tt-env-manifests-proto1-main"
  TT_FAKE_ARCHIVE="$archive_path"
  export GITHUB_TOKEN="env-token"

  PATH="${fake_bin}:${PATH}" run "$TT_ENV" update

  [ "$status" -eq 0 ]
  [ -f "${TT_HOME}/releases/2024.2.json" ]
  [ ! -e "${TT_HOME}/releases/2024.2.json.asc" ]
  [ ! -e "${TT_HOME}/manifests/ubuntu-22.04.env.asc" ]
}
