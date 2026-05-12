#!/usr/bin/env bats

setup() {
  TT_ENV="${BATS_TEST_DIRNAME}/../../bin/tt-env"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export TT_HOME="${BATS_TEST_TMPDIR}/tt-home"
  export TT_FAKE_CURL_URL_LOG="${BATS_TEST_TMPDIR}/mirror-urls.log"
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

make_manifest_archive() {
  local archive_path="${BATS_TEST_TMPDIR}/mirror-manifests.tar.gz"
  local source_root="${BATS_TEST_TMPDIR}/mirror-archive-source"
  local repo_root="${source_root}/tt-env-manifests-proto1-main"

  rm -rf "$source_root"
  mkdir -p "${repo_root}/manifests"
  write_release_manifest "$repo_root" "2024.3"
  printf 'PKG_MANAGER="apt"\n' >"${repo_root}/manifests/ubuntu-22.04.env"
  tar -czf "$archive_path" -C "$source_root" "tt-env-manifests-proto1-main"
  printf '%s\n' "$archive_path"
}

make_fake_mirror_tools() {
  local fake_bin="${BATS_TEST_TMPDIR}/fake-update-mirror-bin"

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
    --write-out|--header|--retry)
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
printf '%s\n' "$url" >>"$TT_FAKE_CURL_URL_LOG"
case "$url" in
  *"$TT_FAKE_SUCCESS_REPO"*)
    cp "$TT_FAKE_ARCHIVE" "$output"
    printf '200'
    ;;
  *)
    : >"$output"
    printf '%s' "${TT_FAKE_CURL_HTTP_CODE:-500}"
    ;;
esac
EOF
  cat >"${fake_bin}/gh" <<'EOF'
#!/bin/sh
exit 1
EOF
  chmod +x "${fake_bin}/curl" "${fake_bin}/gh"
  printf '%s\n' "$fake_bin"
}

@test "tt-env update falls through to the second mirror" {
  fake_bin="$(make_fake_mirror_tools)"
  export TT_FAKE_ARCHIVE
  TT_FAKE_ARCHIVE="$(make_manifest_archive)"
  export TT_FAKE_SUCCESS_REPO="mirror-two/tt-env-manifests"
  export GITHUB_TOKEN="env-token"
  mkdir -p "$TT_HOME"
  cat >"${TT_HOME}/config" <<'EOF'
MIRRORS=(
  "mirror-one/tt-env-manifests"
  "mirror-two/tt-env-manifests"
)
EOF

  PATH="${fake_bin}:${PATH}" run "$TT_ENV" update

  [ "$status" -eq 0 ]
  [ -f "${TT_HOME}/releases/2024.3.json" ]
  [ "$(sed -n '1p' "$TT_FAKE_CURL_URL_LOG")" = "https://api.github.com/repos/mirror-one/tt-env-manifests/tarball/main" ]
  [ "$(sed -n '2p' "$TT_FAKE_CURL_URL_LOG")" = "https://api.github.com/repos/mirror-two/tt-env-manifests/tarball/main" ]
  [[ "$output" == *"Updated manifests from mirror-two/tt-env-manifests@main"* ]]
}

@test "tt-env update falls back to default after mirrors fail" {
  fake_bin="$(make_fake_mirror_tools)"
  export TT_FAKE_ARCHIVE
  TT_FAKE_ARCHIVE="$(make_manifest_archive)"
  export TT_FAKE_SUCCESS_REPO="tetsuh/tt-env-manifests-proto1"
  export GITHUB_TOKEN="env-token"
  mkdir -p "$TT_HOME"
  cat >"${TT_HOME}/config" <<'EOF'
MIRRORS=(
  "mirror-one/tt-env-manifests"
)
EOF

  PATH="${fake_bin}:${PATH}" run "$TT_ENV" update

  [ "$status" -eq 0 ]
  [ "$(sed -n '1p' "$TT_FAKE_CURL_URL_LOG")" = "https://api.github.com/repos/mirror-one/tt-env-manifests/tarball/main" ]
  [ "$(sed -n '2p' "$TT_FAKE_CURL_URL_LOG")" = "https://api.github.com/repos/tetsuh/tt-env-manifests-proto1/tarball/main" ]
  [[ "$output" == *"Updated manifests from tetsuh/tt-env-manifests-proto1@main"* ]]
}

@test "tt-env update fails clearly when all mirrors are down" {
  fake_bin="$(make_fake_mirror_tools)"
  export TT_FAKE_ARCHIVE
  TT_FAKE_ARCHIVE="$(make_manifest_archive)"
  export TT_FAKE_SUCCESS_REPO="none/available"
  export GITHUB_TOKEN="env-token"
  mkdir -p "${TT_HOME}/releases" "${TT_HOME}/manifests"
  printf 'old release\n' >"${TT_HOME}/releases/old.json"
  printf 'old manifest\n' >"${TT_HOME}/manifests/old.env"
  cat >"${TT_HOME}/config" <<'EOF'
MIRRORS=(
  "mirror-one/tt-env-manifests"
  "mirror-two/tt-env-manifests"
)
EOF

  PATH="${fake_bin}:${PATH}" run "$TT_ENV" update

  [ "$status" -ne 0 ]
  [[ "$output" == *"Failed to fetch manifests from all configured sources"* ]]
  [ "$(wc -l <"$TT_FAKE_CURL_URL_LOG")" -eq 3 ]
  [ "$(cat "${TT_HOME}/releases/old.json")" = "old release" ]
  [ "$(cat "${TT_HOME}/manifests/old.env")" = "old manifest" ]
}

