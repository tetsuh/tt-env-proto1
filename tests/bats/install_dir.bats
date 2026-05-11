#!/usr/bin/env bats

setup() {
  TT_ENV="${BATS_TEST_DIRNAME}/../../bin/tt-env"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export TT_HOME="${BATS_TEST_TMPDIR}/tt-home"
  export TT_OVERRIDE_OS_ID="ubuntu"
  export TT_OVERRIDE_OS_VERSION="22.04"

  mkdir -p "${TT_HOME}/manifests" "${BATS_TEST_TMPDIR}/bin"
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

  mkdir -p "${TT_HOME}/releases" "${BATS_TEST_TMPDIR}/assets"
  for component in tt-kmd tt-smi firmware tt-metal; do
    printf 'asset:%s\n' "$component" >"${BATS_TEST_TMPDIR}/assets/${component}"
  done

  tt_kmd_sha="$(sha256sum "${BATS_TEST_TMPDIR}/assets/tt-kmd")"
  tt_smi_sha="$(sha256sum "${BATS_TEST_TMPDIR}/assets/tt-smi")"
  firmware_sha="$(sha256sum "${BATS_TEST_TMPDIR}/assets/firmware")"
  tt_metal_sha="$(sha256sum "${BATS_TEST_TMPDIR}/assets/tt-metal")"

  cat >"${TT_HOME}/releases/2024.1.json" <<EOF
{
  "release": "2024.1",
  "description": "Test release",
  "components": {
    "tt-kmd": {
      "version": "v2.5.0",
      "download_url": "file://${BATS_TEST_TMPDIR}/assets/tt-kmd",
      "sha256": "${tt_kmd_sha%% *}"
    },
    "tt-smi": {
      "version": "v3.0.38",
      "download_url": "file://${BATS_TEST_TMPDIR}/assets/tt-smi",
      "sha256": "${tt_smi_sha%% *}"
    },
    "firmware": {
      "version": "19.2.0",
      "download_url": "file://${BATS_TEST_TMPDIR}/assets/firmware",
      "sha256": "${firmware_sha%% *}"
    },
    "tt-metal": {
      "version": "v0.65.0",
      "download_url": "file://${BATS_TEST_TMPDIR}/assets/tt-metal",
      "sha256": "${tt_metal_sha%% *}"
    }
  }
}
EOF
}

@test "tt-env install creates a per-release version directory" {
  run "$TT_ENV" install 2024.1
  [ "$status" -eq 0 ]
  [ -d "${TT_HOME}/versions/2024.1" ]
  [ -f "${TT_HOME}/versions/2024.1/.tt-env-installed" ]
  [[ "$output" == *"Installed release 2024.1"* ]]
}

@test "tt-env install is a no-op when release is already installed" {
  run "$TT_ENV" install 2024.1
  [ "$status" -eq 0 ]

  run "$TT_ENV" install 2024.1
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
}

@test "tt-env install --force re-creates the version directory" {
  run "$TT_ENV" install 2024.1
  [ "$status" -eq 0 ]

  touch "${TT_HOME}/versions/2024.1/sentinel"

  run "$TT_ENV" install --force 2024.1
  [ "$status" -eq 0 ]
  [ -d "${TT_HOME}/versions/2024.1" ]
  [ -f "${TT_HOME}/versions/2024.1/.tt-env-installed" ]
  [ ! -d "${TT_HOME}/versions/2024.1/.2024.1.partial" ]
  [ ! -e "${TT_HOME}/versions/2024.1/sentinel" ]
  [[ "$output" == *"Removing existing version directory"* ]]
}

@test "tt-env install --dry-run prints planned actions without creating the directory" {
  run "$TT_ENV" install --dry-run 2024.1
  [ "$status" -eq 0 ]
  [ ! -e "${TT_HOME}/versions/2024.1" ]
  [[ "$output" == *"[dry-run] Would create version directory"* ]]
}

@test "tt-env install rejects unsafe release names" {
  run "$TT_ENV" install ..
  [ "$status" -eq 1 ]
  [[ "$output" == *"Invalid release name: .."* ]]

  [ ! -e "${TT_HOME}/versions" ] || [ -z "$(find "${TT_HOME}/versions" -mindepth 1 -print -quit)" ]
}

@test "tt-env install fails when the release manifest is missing" {
  run "$TT_ENV" install 2099.9
  [ "$status" -eq 1 ]
  [[ "$output" == *"Release manifest not found for 2099.9"* ]]
  [ ! -e "${TT_HOME}/versions/2099.9" ]
}

@test "tt-env install refuses an unmarked existing version directory without --force" {
  mkdir -p "${TT_HOME}/versions/2024.1"

  run "$TT_ENV" install 2024.1
  [ "$status" -eq 1 ]
  [[ "$output" == *"Version directory exists but is not marked installed"* ]]
}
