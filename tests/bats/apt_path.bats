#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/test_helpers.bash"
  install_test_setup_common
  write_install_os_manifest "true" "https://repo.example.invalid/tenstorrent"
}

@test "tt-env install adds required repos before apt install" {
  fake_bin="$(make_fake_sudo)"

  run env PATH="${fake_bin}:${PATH}" "$TT_ENV" install proto-stack-2026.05.16
  [ "$status" -eq 0 ]
  [ -d "${TT_HOME}/versions/proto-stack-2026.05.16" ]

  mapfile -t apt_calls <"$TT_APT_LOG"
  [ "${apt_calls[0]}" = "add-apt-repository -y https://repo.example.invalid/tenstorrent" ]
  [ "${apt_calls[1]}" = "apt-get update" ]
  [ "${apt_calls[2]}" = "apt-get install -y cmake ninja-build zlib1g-dev tenstorrent-dkms" ]
}

@test "tt-env install fails clearly when sudo is missing" {
  bash_env="$(make_command_absent_env sudo)"

  run env BASH_ENV="$bash_env" "$TT_ENV" install proto-stack-2026.05.16
  [ "$status" -eq 1 ]
  [[ "$output" == *"sudo is required to install apt packages"* ]]
  [ ! -e "${TT_HOME}/versions/proto-stack-2026.05.16" ]
}

@test "tt-env install fails clearly when add-apt-repository is missing" {
  fake_bin="$(make_fake_sudo)"
  bash_env="$(make_command_absent_env add-apt-repository)"

  run env BASH_ENV="$bash_env" PATH="${fake_bin}:${PATH}" "$TT_ENV" install proto-stack-2026.05.16
  [ "$status" -eq 1 ]
  [[ "$output" == *"add-apt-repository is required to add repositories"* ]]
  [ ! -e "${TT_HOME}/versions/proto-stack-2026.05.16" ]
}

@test "tt-env install --dry-run reports apt actions without sudo" {
  bash_env="$(make_command_absent_env sudo)"

  run env BASH_ENV="$bash_env" "$TT_ENV" install --dry-run proto-stack-2026.05.16
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] Would add apt repository: https://repo.example.invalid/tenstorrent"* ]]
  [[ "$output" == *"[dry-run] Would install apt packages: cmake ninja-build zlib1g-dev tenstorrent-dkms"* ]]
  [ ! -e "${TT_HOME}/versions/proto-stack-2026.05.16" ]
}

@test "repository apt manifests disable placeholder PPA before apt mutation" {
  repo_dir="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  fake_bin="$(make_fake_sudo)"
  mkdir -p "${TT_HOME}/manifests" "${TT_HOME}/releases"
  cp "${repo_dir}/manifests/ubuntu-22.04.env" "${TT_HOME}/manifests/ubuntu-22.04.env"
  cp "${repo_dir}/releases/proto-stack-2026.05.16.json" "${TT_HOME}/releases/proto-stack-2026.05.16.json"

  run env PATH="${fake_bin}:${PATH}" "$TT_ENV" install proto-stack-2026.05.16
  [ "$status" -eq 1 ]
  [[ "$output" == *"System package install path is disabled"* ]]
  [[ "$output" == *"requires download_url and sha256 when system package installation is disabled"* ]]
  [ ! -e "${TT_HOME}/versions/proto-stack-2026.05.16" ]
  [ ! -s "$TT_APT_LOG" ]
}

@test "tt-env install selects Ubuntu 24.04 OS manifest when overridden" {
  mkdir -p "${TT_HOME}/manifests"
  cat >"${TT_HOME}/manifests/ubuntu-24.04.env" <<'EOF'
PKG_MANAGER="apt"
USE_SYSTEM_PACKAGES="true"
REQUIRED_REPOS=()
VIRT_PKG_CMAKE="cmake-24"
VIRT_PKG_NINJA="ninja-build-24"
VIRT_PKG_ZLIB="zlib1g-dev-24"
VIRT_PKG_KMD="tenstorrent-dkms-24"
WORKAROUNDS=()
EOF
  bash_env="$(make_command_absent_env sudo)"

  run env BASH_ENV="$bash_env" TT_OVERRIDE_OS_ID=ubuntu TT_OVERRIDE_OS_VERSION=24.04 \
    "$TT_ENV" install --dry-run proto-stack-2026.05.16
  [ "$status" -eq 0 ]
  [[ "$output" == *"Using override OS: ubuntu 24.04"* ]]
  [[ "$output" == *"[dry-run] Would install apt packages: cmake-24 ninja-build-24 zlib1g-dev-24 tenstorrent-dkms-24"* ]]
  [ ! -e "${TT_HOME}/versions/proto-stack-2026.05.16" ]
}

@test "tt-env install selects Linux Mint 22.1 OS manifest when overridden" {
  mkdir -p "${TT_HOME}/manifests"
  cat >"${TT_HOME}/manifests/linuxmint-22.1.env" <<'EOF'
PKG_MANAGER="apt"
USE_SYSTEM_PACKAGES="true"
REQUIRED_REPOS=()
VIRT_PKG_CMAKE="cmake-mint"
VIRT_PKG_NINJA="ninja-build-mint"
VIRT_PKG_ZLIB="zlib1g-dev-mint"
VIRT_PKG_KMD="tenstorrent-dkms-mint"
WORKAROUNDS=()
EOF
  bash_env="$(make_command_absent_env sudo)"

  run env BASH_ENV="$bash_env" TT_OVERRIDE_OS_ID=linuxmint TT_OVERRIDE_OS_VERSION=22.1 \
    "$TT_ENV" install --dry-run proto-stack-2026.05.16
  [ "$status" -eq 0 ]
  [[ "$output" == *"Using override OS: linuxmint 22.1"* ]]
  [[ "$output" == *"[dry-run] Would install apt packages: cmake-mint ninja-build-mint zlib1g-dev-mint tenstorrent-dkms-mint"* ]]
  [ ! -e "${TT_HOME}/versions/proto-stack-2026.05.16" ]
}
