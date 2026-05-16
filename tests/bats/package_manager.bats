#!/usr/bin/env bats

setup() {
  PACKAGE_MANAGER_SH="${BATS_TEST_DIRNAME}/../../lib/package_manager.sh"
  manifest_file="${BATS_TEST_TMPDIR}/ubuntu-22.04.env"
  dnf_manifest_file="${BATS_TEST_TMPDIR}/fedora-40.env"
  export TT_PKG_LOG="${BATS_TEST_TMPDIR}/pkg.log"
  cat >"$manifest_file" <<'EOF'
PKG_MANAGER="apt"
USE_PPA="true"
REQUIRED_REPOS=(
  "https://ppa.tenstorrent.com/ubuntu/"
)
VIRT_PKG_CMAKE="cmake"
VIRT_PKG_NINJA="ninja-build"
VIRT_PKG_ZLIB="zlib1g-dev"
VIRT_PKG_KMD="tenstorrent-dkms"
WORKAROUNDS=()
EOF
  cat >"$dnf_manifest_file" <<'EOF'
PKG_MANAGER="dnf"
USE_SYSTEM_PACKAGES="true"
REQUIRED_REPOS=(
  "https://repo.example.invalid/tenstorrent.repo"
)
VIRT_PKG_CMAKE="cmake"
VIRT_PKG_NINJA="ninja-build"
VIRT_PKG_ZLIB="zlib-devel"
VIRT_PKG_KMD="tenstorrent-dkms"
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

make_fake_sudo_only() {
  local fake_bin="${BATS_TEST_TMPDIR}/fake-sudo-bin"

  mkdir -p "$fake_bin"
  cat >"${fake_bin}/sudo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TT_PKG_LOG"
EOF
  chmod +x "${fake_bin}/sudo"
  printf '%s\n' "$fake_bin"
}

make_fake_dnf_without_config_manager() {
  local fake_bin="${BATS_TEST_TMPDIR}/fake-dnf-no-config-manager-bin"

  mkdir -p "$fake_bin"
  cat >"${fake_bin}/sudo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TT_PKG_LOG"
EOF
  cat >"${fake_bin}/dnf" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "config-manager" ]]; then
  exit 1
fi
exit 0
EOF
  chmod +x "${fake_bin}/sudo" "${fake_bin}/dnf"
  printf '%s\n' "$fake_bin"
}

@test "package manager dispatcher runs apt dry-run from parsed manifest" {
  run bash -c 'source "$1"; parse_env_manifest "$2"; package_manager_install_system_packages apt 1' \
    bash "$PACKAGE_MANAGER_SH" "$manifest_file"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] Would add apt repository: https://ppa.tenstorrent.com/ubuntu/"* ]]
  [[ "$output" == *"[dry-run] Would run apt-get update."* ]]
  [[ "$output" == *"[dry-run] Would install apt packages: cmake ninja-build zlib1g-dev tenstorrent-dkms"* ]]
}

@test "package manager dispatcher rejects unsupported managers" {
  run bash -c 'source "$1"; package_manager_install_system_packages zypper 1' \
    bash "$PACKAGE_MANAGER_SH"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unsupported package manager for install: zypper"* ]]
}

@test "package manager dispatcher requires parsed package mappings" {
  run bash -c 'source "$1"; package_manager_install_system_packages apt 1' \
    bash "$PACKAGE_MANAGER_SH"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Virtual package is not defined: cmake"* ]]
}

@test "package manager dispatcher runs dnf dry-run from parsed manifest" {
  run bash -c 'source "$1"; parse_env_manifest "$2"; package_manager_install_system_packages dnf 1' \
    bash "$PACKAGE_MANAGER_SH" "$dnf_manifest_file"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] Would add dnf repository: https://repo.example.invalid/tenstorrent.repo"* ]]
  [[ "$output" == *"[dry-run] Would run dnf makecache."* ]]
  [[ "$output" == *"[dry-run] Would install dnf packages: cmake ninja-build zlib-devel tenstorrent-dkms"* ]]
}

@test "package manager dispatcher runs dnf repo cache and install commands" {
  fake_bin="$(make_fake_dnf_sudo)"

  run env PATH="${fake_bin}:${PATH}" TT_PKG_LOG="$TT_PKG_LOG" \
    bash -c 'source "$1"; parse_env_manifest "$2"; package_manager_install_system_packages dnf 0' \
    bash "$PACKAGE_MANAGER_SH" "$dnf_manifest_file"
  [ "$status" -eq 0 ]

  mapfile -t dnf_calls <"$TT_PKG_LOG"
  [ "${dnf_calls[0]}" = "dnf config-manager --add-repo https://repo.example.invalid/tenstorrent.repo" ]
  [ "${dnf_calls[1]}" = "dnf makecache" ]
  [ "${dnf_calls[2]}" = "dnf install -y cmake ninja-build zlib-devel tenstorrent-dkms" ]
}

@test "package manager dispatcher fails clearly when dnf is missing" {
  fake_bin="$(make_fake_sudo_only)"

  run env PATH="${fake_bin}:${PATH}" TT_PKG_LOG="$TT_PKG_LOG" \
    bash -c 'source "$1"; parse_env_manifest "$2"; package_manager_install_system_packages dnf 0' \
    bash "$PACKAGE_MANAGER_SH" "$dnf_manifest_file"
  [ "$status" -eq 1 ]
  [[ "$output" == *"dnf is required to install dnf packages"* ]]
}

@test "package manager dispatcher fails clearly when dnf config-manager is missing for repos" {
  fake_bin="$(make_fake_dnf_without_config_manager)"

  run env PATH="${fake_bin}:${PATH}" TT_PKG_LOG="$TT_PKG_LOG" \
    bash -c 'source "$1"; parse_env_manifest "$2"; package_manager_install_system_packages dnf 0' \
    bash "$PACKAGE_MANAGER_SH" "$dnf_manifest_file"
  [ "$status" -eq 1 ]
  [[ "$output" == *"dnf config-manager is required to add repositories"* ]]
}
