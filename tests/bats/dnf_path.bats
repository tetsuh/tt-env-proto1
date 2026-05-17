#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/test_helpers.bash"
  install_test_setup_common
  export TT_PKG_LOG="${BATS_TEST_TMPDIR}/pkg.log"

  mkdir -p "${TT_HOME}/manifests"
  cat >"${TT_HOME}/manifests/ubuntu-22.04.env" <<'EOF'
PKG_MANAGER="dnf"
USE_SYSTEM_PACKAGES="true"
REQUIRED_REPOS=(
  "https://repo.example.invalid/tenstorrent.repo"
)
VIRT_PKG_CMAKE="cmake"
VIRT_PKG_NINJA="ninja-build"
VIRT_PKG_ZLIB="zlib-devel"
VIRT_PKG_KMD="tenstorrent-dkms"
VIRT_PKG_SMI="tt-smi"
VIRT_PKG_FLASH="tt-flash"
VIRT_PKG_TOPOLOGY="tt-topology"
WORKAROUNDS=()
EOF
}

make_fake_dnf_sudo() {
  local fake_bin="${BATS_TEST_TMPDIR}/fake-dnf-bin"

  mkdir -p "$fake_bin"
  cat >"${fake_bin}/sudo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TT_PKG_LOG"
EOF
  touch "${fake_bin}/dnf"
  chmod +x "${fake_bin}/sudo" "${fake_bin}/dnf"
  printf '%s\n' "$fake_bin"
}

@test "tt-env install can use a dnf OS manifest" {
  fake_bin="$(make_fake_dnf_sudo)"

  run env PATH="${fake_bin}:${PATH}" "$TT_ENV" install 2026.05.16
  [ "$status" -eq 0 ]
  [ -d "${TT_HOME}/versions/2026.05.16" ]

  mapfile -t dnf_calls <"$TT_PKG_LOG"
  [ "${dnf_calls[0]}" = "dnf config-manager --add-repo https://repo.example.invalid/tenstorrent.repo" ]
  [ "${dnf_calls[1]}" = "dnf makecache" ]
  [ "${dnf_calls[2]}" = "dnf install -y cmake ninja-build zlib-devel tenstorrent-dkms tt-smi tt-flash tt-topology" ]
}
