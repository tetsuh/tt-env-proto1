#!/usr/bin/env bats

setup() {
  TT_ENV="${BATS_TEST_DIRNAME}/../../bin/tt-env"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export TT_HOME="${BATS_TEST_TMPDIR}/tt-home"
  export TT_OVERRIDE_OS_ID="ubuntu"
  export TT_OVERRIDE_OS_VERSION="22.04"
  export TT_APT_LOG="${BATS_TEST_TMPDIR}/apt.log"
  export TT_CURL_LOG="${BATS_TEST_TMPDIR}/curl.log"
}

write_apt_manifest() {
  mkdir -p "${TT_HOME}/manifests"
  cat >"${TT_HOME}/manifests/ubuntu-22.04.env" <<'EOF'
PKG_MANAGER="apt"
USE_PPA="true"
REQUIRED_REPOS=(
  "ppa:tenstorrent/ppa"
)
VIRT_PKG_CMAKE="cmake"
VIRT_PKG_NINJA="ninja-build"
VIRT_PKG_ZLIB="zlib1g-dev"
VIRT_PKG_KMD="tt-kmd-dkms"
WORKAROUNDS=()
EOF
}

make_fake_sudo() {
  fake_bin="${BATS_TEST_TMPDIR}/fake-apt-bin"
  mkdir -p "$fake_bin"
  cat >"${fake_bin}/sudo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TT_APT_LOG"
EOF
  chmod +x "${fake_bin}/sudo"
  touch "${fake_bin}/add-apt-repository" "${fake_bin}/apt-get"
  chmod +x "${fake_bin}/add-apt-repository" "${fake_bin}/apt-get"
  printf '%s\n' "$fake_bin"
}

write_download_manifest() {
  mkdir -p "${TT_HOME}/manifests" "${TT_HOME}/releases" "${BATS_TEST_TMPDIR}/assets"
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
    printf 'idempotent:%s\n' "$component" >"${BATS_TEST_TMPDIR}/assets/${component}"
  done

  write_download_release_manifest
}

sha_for_asset() {
  local output
  output="$(sha256sum "${BATS_TEST_TMPDIR}/assets/$1")"
  printf '%s\n' "${output%% *}"
}

write_download_release_manifest() {
  cat >"${TT_HOME}/releases/2024.1.json" <<EOF
{
  "release": "2024.1",
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
      "sha256": "$(sha_for_asset firmware)"
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

make_fake_curl() {
  fake_bin="${BATS_TEST_TMPDIR}/fake-curl-bin"
  mkdir -p "$fake_bin"
  cat >"${fake_bin}/curl" <<'EOF'
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
printf '%s\n' "$url" >>"$TT_CURL_LOG"
cp "${url#file://}" "$output"
EOF
  chmod +x "${fake_bin}/curl"
  printf '%s\n' "$fake_bin"
}

@test "second install is a no-op and does not rerun download path" {
  fake_bin="$(make_fake_curl)"
  write_download_manifest

  run env PATH="${fake_bin}:${PATH}" "$TT_ENV" install 2024.1
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$TT_CURL_LOG")" -eq 4 ]

  run env PATH="${fake_bin}:${PATH}" "$TT_ENV" install 2024.1
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
  [ "$(wc -l <"$TT_CURL_LOG")" -eq 4 ]
}

@test "tt-env install --force reruns apt path from scratch" {
  fake_bin="$(make_fake_sudo)"
  write_apt_manifest

  run env PATH="${fake_bin}:${PATH}" "$TT_ENV" install 2024.1
  [ "$status" -eq 0 ]

  run env PATH="${fake_bin}:${PATH}" "$TT_ENV" install 2024.1
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]

  run env PATH="${fake_bin}:${PATH}" "$TT_ENV" install --force 2024.1
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$TT_APT_LOG")" -eq 6 ]
}

@test "tt-env install --force reruns download path from scratch" {
  fake_bin="$(make_fake_curl)"
  write_download_manifest

  run env PATH="${fake_bin}:${PATH}" "$TT_ENV" install 2024.1
  [ "$status" -eq 0 ]

  run env PATH="${fake_bin}:${PATH}" "$TT_ENV" install 2024.1
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]

  run env PATH="${fake_bin}:${PATH}" "$TT_ENV" install --force 2024.1
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$TT_CURL_LOG")" -eq 8 ]
}
