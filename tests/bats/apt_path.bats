#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/test_helpers.bash"
  install_test_setup_common
  write_install_os_manifest "true" "https://ppa.tenstorrent.com/ubuntu/"
}

@test "tt-env install adds official Tenstorrent repo before apt install" {
  fake_bin="$(make_fake_sudo)"

  run env PATH="${fake_bin}:${PATH}" "$TT_ENV" install proto-stack-2026.05.16
  [ "$status" -eq 0 ]
  [ -d "${TT_HOME}/versions/proto-stack-2026.05.16" ]

  mapfile -t apt_calls <"$TT_APT_LOG"
  [ "${apt_calls[0]}" = "install -d -m 0755 /etc/apt/keyrings" ]
  [[ "${apt_calls[1]}" == install\ -m\ 0644\ *\ /etc/apt/keyrings/tt-pkg-key.asc ]]
  [ "${apt_calls[2]}" = "tee /etc/apt/sources.list.d/tenstorrent.list" ]
  [ "${apt_calls[3]}" = "apt-get update" ]
  [ "${apt_calls[4]}" = "apt-get install -y cmake ninja-build zlib1g-dev tenstorrent-dkms" ]
}

@test "tt-env install fails clearly when sudo is missing" {
  bash_env="$(make_command_absent_env sudo)"

  run env BASH_ENV="$bash_env" "$TT_ENV" install proto-stack-2026.05.16
  [ "$status" -eq 1 ]
  [[ "$output" == *"sudo is required to install apt packages"* ]]
  [ ! -e "${TT_HOME}/versions/proto-stack-2026.05.16" ]
}

@test "tt-env install does not require add-apt-repository for official Tenstorrent repo" {
  fake_bin="$(make_fake_sudo)"
  bash_env="$(make_command_absent_env add-apt-repository)"

  run env BASH_ENV="$bash_env" PATH="${fake_bin}:${PATH}" "$TT_ENV" install proto-stack-2026.05.16
  [ "$status" -eq 0 ]
  [ -d "${TT_HOME}/versions/proto-stack-2026.05.16" ]
}

@test "tt-env install still requires add-apt-repository for generic apt repos" {
  write_install_os_manifest "true" "https://repo.example.invalid/tenstorrent"
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
  [[ "$output" == *"[dry-run] Would create apt keyring directory: /etc/apt/keyrings"* ]]
  [[ "$output" == *"[dry-run] Would download Tenstorrent apt signing key: https://ppa.tenstorrent.com/tt-pkg-key.asc"* ]]
  [[ "$output" == *"[dry-run] Would verify Tenstorrent apt signing key fingerprint: 58540CD771C55DD7C33030CA8A9D565F6A208463"* ]]
  [[ "$output" == *"[dry-run] Would write apt source /etc/apt/sources.list.d/tenstorrent.list: deb [arch=amd64 signed-by=/etc/apt/keyrings/tt-pkg-key.asc] https://ppa.tenstorrent.com/ubuntu/ jammy main"* ]]
  [[ "$output" == *"[dry-run] Would install apt packages: cmake ninja-build zlib1g-dev tenstorrent-dkms"* ]]
  [ ! -e "${TT_HOME}/versions/proto-stack-2026.05.16" ]
}

@test "repository apt manifests use official Tenstorrent repo" {
  repo_dir="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  fake_bin="$(make_fake_sudo)"
  mkdir -p "${TT_HOME}/manifests" "${TT_HOME}/releases"
  cp "${repo_dir}/manifests/ubuntu-22.04.env" "${TT_HOME}/manifests/ubuntu-22.04.env"
  cp "${repo_dir}/releases/proto-stack-2026.05.16.json" "${TT_HOME}/releases/proto-stack-2026.05.16.json"

  run env PATH="${fake_bin}:${PATH}" "$TT_ENV" install proto-stack-2026.05.16
  [ "$status" -eq 0 ]
  [ -d "${TT_HOME}/versions/proto-stack-2026.05.16" ]
  mapfile -t apt_calls <"$TT_APT_LOG"
  [ "${apt_calls[0]}" = "install -d -m 0755 /etc/apt/keyrings" ]
  [[ "${apt_calls[1]}" == install\ -m\ 0644\ *\ /etc/apt/keyrings/tt-pkg-key.asc ]]
  [ "${apt_calls[4]}" = "apt-get install -y cmake ninja-build zlib1g-dev tenstorrent-dkms" ]
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

@test "tt-env install uses UBUNTU_CODENAME for official repo on Linux Mint" {
  write_test_os_release linuxmint "22.1" wilma noble
  mkdir -p "${TT_HOME}/manifests"
  cat >"${TT_HOME}/manifests/linuxmint-22.1.env" <<'EOF'
PKG_MANAGER="apt"
USE_SYSTEM_PACKAGES="true"
REQUIRED_REPOS=(
  "https://ppa.tenstorrent.com/ubuntu/"
)
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
  [[ "$output" == *"deb [arch=amd64 signed-by=/etc/apt/keyrings/tt-pkg-key.asc] https://ppa.tenstorrent.com/ubuntu/ noble main"* ]]
  [ ! -e "${TT_HOME}/versions/proto-stack-2026.05.16" ]
}

@test "tt-env install fails before apt mutation for unsupported Tenstorrent repo codename" {
  write_test_os_release ubuntu "26.04" resolute ""
  fake_bin="$(make_fake_sudo)"

  run env PATH="${fake_bin}:${PATH}" "$TT_ENV" install proto-stack-2026.05.16
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unsupported Tenstorrent apt repository codename 'resolute'"* ]]
  [ ! -e "${TT_HOME}/versions/proto-stack-2026.05.16" ]
  [ ! -s "$TT_APT_LOG" ]
}

@test "tt-env install fails before apt mutation when curl is missing for official repo" {
  fake_bin="$(make_fake_sudo)"
  bash_env="$(make_command_absent_env curl)"

  run env BASH_ENV="$bash_env" PATH="${fake_bin}:${PATH}" "$TT_ENV" install proto-stack-2026.05.16
  [ "$status" -eq 1 ]
  [[ "$output" == *"curl is required to download the Tenstorrent apt signing key"* ]]
  [ ! -e "${TT_HOME}/versions/proto-stack-2026.05.16" ]
  [ ! -s "$TT_APT_LOG" ]
}

@test "tt-env install fails before apt mutation when Tenstorrent key fingerprint mismatches" {
  fake_bin="$(make_fake_sudo)"
  cat >"${fake_bin}/gpg" <<'EOF'
#!/usr/bin/env bash
printf 'pub:::::::::\n'
printf 'fpr:::::::::0000000000000000000000000000000000000000:\n'
EOF
  chmod +x "${fake_bin}/gpg"

  run env PATH="${fake_bin}:${PATH}" "$TT_ENV" install proto-stack-2026.05.16
  [ "$status" -eq 1 ]
  [[ "$output" == *"Tenstorrent apt signing key fingerprint mismatch"* ]]
  [ ! -e "${TT_HOME}/versions/proto-stack-2026.05.16" ]
  [ ! -s "$TT_APT_LOG" ]
}
