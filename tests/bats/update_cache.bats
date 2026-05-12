#!/usr/bin/env bats

setup() {
  TT_ENV="${BATS_TEST_DIRNAME}/../../bin/tt-env"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export TT_HOME="${BATS_TEST_TMPDIR}/tt-home"
  export TT_UPDATE_NOW_EPOCH=1700000000
  export TT_STATUS_NOW_EPOCH=1700000000
  export TT_FAKE_CURL_LOG="${BATS_TEST_TMPDIR}/update-curl.log"
  export TT_STATUS_LSPCI_FIXTURE="${BATS_TEST_TMPDIR}/lspci-empty.txt"
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
  local archive_path="${BATS_TEST_TMPDIR}/cache-manifests.tar.gz"
  local source_root="${BATS_TEST_TMPDIR}/cache-archive-source"
  local repo_root="${source_root}/tt-env-manifests-proto1-main"

  rm -rf "$source_root"
  mkdir -p "${repo_root}/manifests"
  write_release_manifest "$repo_root" "2024.2"
  printf 'PKG_MANAGER="apt"\n' >"${repo_root}/manifests/ubuntu-22.04.env"
  write_manifest_signatures "$repo_root"
  tar -czf "$archive_path" -C "$source_root" "tt-env-manifests-proto1-main"
  printf '%s\n' "$archive_path"
}

make_fake_cache_tools() {
  local fake_bin="${BATS_TEST_TMPDIR}/fake-update-cache-bin"

  mkdir -p "$fake_bin"
  cat >"${fake_bin}/curl" <<'EOF'
#!/bin/sh
output=""
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
      shift
      ;;
  esac
done
printf 'fetch\n' >>"$TT_FAKE_CURL_LOG"
cp "$TT_FAKE_ARCHIVE" "$output"
printf '200'
EOF
  cat >"${fake_bin}/gh" <<'EOF'
#!/bin/sh
exit 1
EOF
  cat >"${fake_bin}/lspci" <<'EOF'
#!/bin/sh
cat "$TT_STATUS_LSPCI_FIXTURE"
EOF
  cat >"${fake_bin}/modinfo" <<'EOF'
#!/bin/sh
exit 1
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
  chmod +x "${fake_bin}/curl" "${fake_bin}/gh" "${fake_bin}/lspci" "${fake_bin}/modinfo" "${fake_bin}/gpg"
  printf '%s\n' "$fake_bin"
}

@test "tt-env list skips automatic fetch within 3 hours" {
  fake_bin="$(make_fake_cache_tools)"
  export TT_FAKE_ARCHIVE
  TT_FAKE_ARCHIVE="$(make_manifest_archive)"
  export GITHUB_TOKEN="env-token"
  mkdir -p "${TT_HOME}/manifests"
  printf '%s\n' "1699989199" >"${TT_HOME}/manifests/last_update"

  PATH="${fake_bin}:${PATH}" run "$TT_ENV" list
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$TT_FAKE_CURL_LOG")" -eq 1 ]
  [ "$(cat "${TT_HOME}/manifests/last_update")" = "1700000000" ]

  PATH="${fake_bin}:${PATH}" run "$TT_ENV" list
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$TT_FAKE_CURL_LOG")" -eq 1 ]
}

@test "tt-env status refreshes stale manifests before reporting freshness" {
  fake_bin="$(make_fake_cache_tools)"
  export TT_FAKE_ARCHIVE
  TT_FAKE_ARCHIVE="$(make_manifest_archive)"
  export GITHUB_TOKEN="env-token"
  mkdir -p "${TT_HOME}/manifests"
  printf '%s\n' "1699989199" >"${TT_HOME}/manifests/last_update"
  printf '%s\n' "" >"$TT_STATUS_LSPCI_FIXTURE"

  PATH="${fake_bin}:${PATH}" run "$TT_ENV" status

  [ "$status" -eq 0 ]
  [ "$(wc -l <"$TT_FAKE_CURL_LOG")" -eq 1 ]
  [[ "$output" == *"Manifest freshness: less than 1 minute ago"* ]]
}

@test "tt-env install attempts refresh when manifests are stale" {
  fake_bin="$(make_fake_cache_tools)"
  export TT_FAKE_ARCHIVE
  TT_FAKE_ARCHIVE="$(make_manifest_archive)"
  export GITHUB_TOKEN="env-token"
  mkdir -p "${TT_HOME}/manifests"
  printf '%s\n' "1699989199" >"${TT_HOME}/manifests/last_update"

  PATH="${fake_bin}:${PATH}" run "$TT_ENV" install 2099.9

  [ "$status" -ne 0 ]
  [ "$(wc -l <"$TT_FAKE_CURL_LOG")" -eq 1 ]
  [[ "$output" == *"Release manifest not found for 2099.9"* ]]
}
