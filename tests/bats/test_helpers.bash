install_test_setup_common() {
  TT_ENV="${BATS_TEST_DIRNAME}/../../bin/tt-env"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export TT_HOME="${BATS_TEST_TMPDIR}/tt-home"
  export TT_OVERRIDE_OS_ID="ubuntu"
  export TT_OVERRIDE_OS_VERSION="22.04"
  export TT_APT_LOG="${BATS_TEST_TMPDIR}/apt.log"
  export TT_CURL_LOG="${BATS_TEST_TMPDIR}/curl.log"
}

write_install_os_manifest() {
  local use_system_packages="$1"
  local required_repo="${2:-}"

  mkdir -p "${TT_HOME}/manifests"
  cat >"${TT_HOME}/manifests/ubuntu-22.04.env" <<EOF
PKG_MANAGER="apt"
USE_SYSTEM_PACKAGES="${use_system_packages}"
REQUIRED_REPOS=(
EOF
  if [[ -n "$required_repo" ]]; then
    printf '  "%s"\n' "$required_repo" >>"${TT_HOME}/manifests/ubuntu-22.04.env"
  fi
  cat >>"${TT_HOME}/manifests/ubuntu-22.04.env" <<'EOF'
)
VIRT_PKG_CMAKE="cmake"
VIRT_PKG_NINJA="ninja-build"
VIRT_PKG_ZLIB="zlib1g-dev"
VIRT_PKG_KMD="tenstorrent-dkms"
WORKAROUNDS=()
EOF
}

make_fake_sudo() {
  local fake_bin="${BATS_TEST_TMPDIR}/fake-apt-bin"

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

make_command_absent_env() {
  local command_name="$1"
  local bash_env="${BATS_TEST_TMPDIR}/${command_name}-absent.bash"

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

write_download_assets() {
  local prefix="$1"
  local component

  mkdir -p "${BATS_TEST_TMPDIR}/assets"
  for component in tt-kmd tt-smi firmware tt-metal; do
    printf '%s:%s\n' "$prefix" "$component" >"${BATS_TEST_TMPDIR}/assets/${component}"
    printf 'signature:%s\n' "$component" >"${BATS_TEST_TMPDIR}/assets/${component}.asc"
  done
}

sha_for_asset() {
  local output

  output="$(sha256sum "${BATS_TEST_TMPDIR}/assets/$1")"
  printf '%s\n' "${output%% *}"
}

write_download_release_manifest() {
  local firmware_sha="${1:-$(sha_for_asset firmware)}"

  mkdir -p "${TT_HOME}/releases"
  cat >"${TT_HOME}/releases/proto-stack-2026.05.16.json" <<EOF
{
  "release": "proto-stack-2026.05.16",
  "components": {
    "tt-kmd": {
      "version": "ttkmd-2.8.0",
      "download_url": "file://${BATS_TEST_TMPDIR}/assets/tt-kmd",
      "sha256": "$(sha_for_asset tt-kmd)"
    },
    "tt-smi": {
      "version": "v5.2.0",
      "download_url": "file://${BATS_TEST_TMPDIR}/assets/tt-smi",
      "sha256": "$(sha_for_asset tt-smi)"
    },
    "firmware": {
      "version": "v19.6.0",
      "download_url": "file://${BATS_TEST_TMPDIR}/assets/firmware",
      "sha256": "${firmware_sha}"
    },
    "tt-metal": {
      "version": "v0.70.1",
      "download_url": "file://${BATS_TEST_TMPDIR}/assets/tt-metal",
      "sha256": "$(sha_for_asset tt-metal)"
    }
  }
}
EOF
}

make_fake_curl() {
  local fake_bin="${BATS_TEST_TMPDIR}/fake-curl-bin"

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
    file://*)
      url="$1"
      shift
      ;;
    *)
      shift
      ;;
  esac
done
if [[ -n "${TT_CURL_LOG:-}" ]]; then
  printf '%s\n' "$url" >>"$TT_CURL_LOG"
fi
cp "${url#file://}" "$output"
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
