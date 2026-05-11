#!/usr/bin/env bats

setup() {
  TT_ENV="${BATS_TEST_DIRNAME}/../../bin/tt-env"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export TT_HOME="${BATS_TEST_TMPDIR}/tt-home"
  export TT_OVERRIDE_OS_ID="ubuntu"
  export TT_OVERRIDE_OS_VERSION="22.04"

  mkdir -p "${TT_HOME}/manifests" "${TT_HOME}/releases" "${BATS_TEST_TMPDIR}/assets" "${BATS_TEST_TMPDIR}/bin"
  cat >"${BATS_TEST_TMPDIR}/bin/curl" <<'EOF'
#!/usr/bin/env bash
output=""
url=""
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --output)
      output="$2"
      shift 2
      ;;
    --*)
      shift
      ;;
    *)
      url="$1"
      shift
      ;;
  esac
done
cp "${url#file://}" "$output"
EOF
  chmod +x "${BATS_TEST_TMPDIR}/bin/curl"
  export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"

  cat >"${TT_HOME}/manifests/ubuntu-22.04.env" <<'EOF'
PKG_MANAGER="apt"
USE_PPA="false"
REQUIRED_REPOS=()
VIRT_PKG_CMAKE="cmake"
VIRT_PKG_NINJA="ninja-build"
VIRT_PKG_ZLIB="zlib1g-dev"
VIRT_PKG_KMD="tt-kmd-dkms"
WORKAROUNDS=()
EOF

  for component in tt-kmd tt-smi firmware tt-metal; do
    printf 'downloaded:%s\n' "$component" >"${BATS_TEST_TMPDIR}/assets/${component}"
  done

  write_download_release_manifest
}

sha_for_asset() {
  local output
  output="$(sha256sum "${BATS_TEST_TMPDIR}/assets/$1")"
  printf '%s\n' "${output%% *}"
}

write_download_release_manifest() {
  local firmware_sha="${1:-$(sha_for_asset firmware)}"

  cat >"${TT_HOME}/releases/2024.1.json" <<EOF
{
  "release": "2024.1",
  "description": "Download test release",
  "components": {
    "tt-kmd": {
      "version": "v2.5.0",
      "download_url": "file://${BATS_TEST_TMPDIR}/assets/tt-kmd",
      "sha256": "$(sha_for_asset tt-kmd)"
    },
    "tt-smi": {
      "version": "v3.0.38",
      "download_url": "file://${BATS_TEST_TMPDIR}/assets/tt-smi",
      "sha256": "$(sha_for_asset tt-smi)"
    },
    "firmware": {
      "version": "19.2.0",
      "download_url": "file://${BATS_TEST_TMPDIR}/assets/firmware",
      "sha256": "${firmware_sha}"
    },
    "tt-metal": {
      "version": "v0.65.0",
      "download_url": "file://${BATS_TEST_TMPDIR}/assets/tt-metal",
      "sha256": "$(sha_for_asset tt-metal)"
    }
  }
}
EOF
}

make_command_absent_env() {
  command_name="$1"
  bash_env="${BATS_TEST_TMPDIR}/${command_name}-absent.bash"
  cat >"$bash_env" <<EOF
command() {
  if [[ "\$1" == "-v" && "\$2" == "--" && "\$3" == "${command_name}" ]]; then
    return 1
  fi
  builtin command "\$@"
}
EOF
  printf '%s\n' "$bash_env"
}

@test "tt-env install downloads release artifacts when PPA is disabled" {
  run "$TT_ENV" install 2024.1
  [ "$status" -eq 0 ]

  for component in tt-kmd tt-smi firmware tt-metal; do
    cmp -s "${BATS_TEST_TMPDIR}/assets/${component}" "${TT_HOME}/versions/2024.1/artifacts/${component}"
  done
}

@test "tt-env install rolls back when sha256 verification fails" {
  write_download_release_manifest "0000000000000000000000000000000000000000000000000000000000000000"

  run "$TT_ENV" install 2024.1
  [ "$status" -eq 1 ]
  [[ "$output" == *"sha256 mismatch for firmware"* ]]
  [ ! -e "${TT_HOME}/versions/2024.1" ]
  [ ! -e "${TT_HOME}/versions/.2024.1.partial" ]
}

@test "tt-env install reports missing download metadata for string components" {
  rm -f "${TT_HOME}/releases/2024.1.json"

  run "$TT_ENV" install 2024.1
  [ "$status" -eq 1 ]
  [[ "$output" == *"requires download_url and sha256 when USE_PPA=false"* ]]
  [ ! -e "${TT_HOME}/versions/2024.1" ]
}

@test "tt-env install --dry-run reports download URLs without creating the version dir" {
  run "$TT_ENV" install --dry-run 2024.1
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] Would download tt-kmd from file://${BATS_TEST_TMPDIR}/assets/tt-kmd"* ]]
  [ ! -e "${TT_HOME}/versions/2024.1" ]
}

@test "tt-env install fails clearly when curl is missing" {
  bash_env="$(make_command_absent_env curl)"

  run env BASH_ENV="$bash_env" "$TT_ENV" install 2024.1
  [ "$status" -eq 1 ]
  [[ "$output" == *"curl is required to download release artifacts"* ]]
  [ ! -e "${TT_HOME}/versions/2024.1" ]
  [ ! -e "${TT_HOME}/versions/.2024.1.partial" ]
}

@test "tt-env install removes stale partial directories before downloading" {
  mkdir -p "${TT_HOME}/versions/.2024.1.partial"
  touch "${TT_HOME}/versions/.2024.1.partial/garbage"

  run "$TT_ENV" install 2024.1
  [ "$status" -eq 0 ]
  [ ! -e "${TT_HOME}/versions/2024.1/garbage" ]
}
