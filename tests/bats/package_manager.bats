#!/usr/bin/env bats

setup() {
  PACKAGE_MANAGER_SH="${BATS_TEST_DIRNAME}/../../lib/package_manager.sh"
  manifest_file="${BATS_TEST_TMPDIR}/ubuntu-22.04.env"
  cat >"$manifest_file" <<'EOF'
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

@test "package manager dispatcher runs apt dry-run from parsed manifest" {
  run bash -c 'source "$1"; parse_env_manifest "$2"; package_manager_install_system_packages apt 1' \
    bash "$PACKAGE_MANAGER_SH" "$manifest_file"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] Would add apt repository: ppa:tenstorrent/ppa"* ]]
  [[ "$output" == *"[dry-run] Would run apt-get update."* ]]
  [[ "$output" == *"[dry-run] Would install apt packages: cmake ninja-build zlib1g-dev tt-kmd-dkms"* ]]
}

@test "package manager dispatcher rejects unsupported managers" {
  run bash -c 'source "$1"; package_manager_install_system_packages dnf 1' \
    bash "$PACKAGE_MANAGER_SH"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unsupported package manager for install: dnf"* ]]
}

@test "package manager dispatcher requires parsed package mappings" {
  run bash -c 'source "$1"; package_manager_install_system_packages apt 1' \
    bash "$PACKAGE_MANAGER_SH"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Virtual package is not defined: cmake"* ]]
}
