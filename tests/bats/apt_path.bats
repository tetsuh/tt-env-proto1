#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/test_helpers.bash"
  install_test_setup_common
  write_install_os_manifest "true" "https://ppa.tenstorrent.com/ubuntu/"
}

@test "tt-env install adds official Tenstorrent repo before apt install" {
  fake_bin="$(make_fake_sudo)"

  run env PATH="${fake_bin}:${PATH}" "$TT_ENV" install 2026.05.16
  [ "$status" -eq 0 ]
  [ -d "${TT_HOME}/versions/2026.05.16" ]

  mapfile -t apt_calls <"$TT_APT_LOG"
  [ "${apt_calls[0]}" = "install -d -m 0755 /etc/apt/keyrings" ]
  [[ "${apt_calls[1]}" == install\ -m\ 0644\ *\ /etc/apt/keyrings/tt-pkg-key.asc ]]
  [ "${apt_calls[2]}" = "tee /etc/apt/sources.list.d/tenstorrent.list" ]
  [ "${apt_calls[3]}" = "apt-get update" ]
  [ "${apt_calls[4]}" = "apt-get install -y cmake ninja-build zlib1g-dev tenstorrent-dkms=2.8.0 tt-smi=5.0.1 tt-flash=3.6.5 tt-topology=1.2.19 tt-burnin=0.4.0" ]

  mapfile -t pip_calls <"$TT_PIP_LOG"
  [[ "${pip_calls[0]}" == venv\ */versions/.2026.05.16.partial/venv ]]
  [[ "${pip_calls[1]}" == -m\ pip\ install\ --disable-pip-version-check* ]]
  for package_pin in "tt-smi==5.2.0" "tt-umd==0.9.5" "textual==0.59.0" "elasticsearch==8.11.0"; do
    [[ "${pip_calls[1]}" == *"$package_pin"* ]]
  done
}

@test "tt-env install links system package commands into the release bin" {
  symlinks_supported || skip "POSIX symlinks are not supported in this environment"
  fake_bin="$(make_fake_sudo)"
  bridge_bin="${BATS_TEST_TMPDIR}/bridge-bin"
  clean_path="$(make_clean_path_without_system_shim_commands)"
  make_fake_system_shim_commands "$fake_bin"
  mkdir -p "${TT_HOME}/shims" "$bridge_bin"
  printf '#!/usr/bin/env bash\nexit 99\n' >"${TT_HOME}/shims/tt-smi"
  chmod +x "${TT_HOME}/shims/tt-smi"
  ln -sfn "${TT_HOME}/shims/tt-smi" "${bridge_bin}/tt-smi"

  run env TT_INSTALL_SYSTEM_COMMAND_DIRS="$fake_bin" PATH="${TT_HOME}/shims:${bridge_bin}:${fake_bin}:${clean_path}" "$TT_ENV" install 2026.05.16
  [ "$status" -eq 0 ]
  [ -x "${TT_HOME}/versions/2026.05.16/bin/tt-smi" ]
  [ ! -L "${TT_HOME}/versions/2026.05.16/bin/tt-smi" ]
  grep -q 'VIRTUAL_ENV="${VENV_DIR}"' "${TT_HOME}/versions/2026.05.16/bin/tt-smi"
  grep -q 'exec "$VENV_PYTHON" "$TARGET_COMMAND" "$@"' "${TT_HOME}/versions/2026.05.16/bin/tt-smi"
  for command_name in tt-flash tt-topology tt-burnin; do
    [ -L "${TT_HOME}/versions/2026.05.16/bin/${command_name}" ]
    [ "$(readlink "${TT_HOME}/versions/2026.05.16/bin/${command_name}")" = "${fake_bin}/${command_name}" ]
  done

  run "$TT_ENV" use 2026.05.16
  [ "$status" -eq 0 ]
  run "${TT_HOME}/shims/tt-smi" probe
  [ "$status" -eq 0 ]
  [ "$output" = "system tt-smi probe" ]
}

@test "tt-env install prefers system command directories over earlier user PATH entries" {
  fake_bin="$(make_fake_sudo)"
  clean_path="$(make_clean_path_without_system_shim_commands)"
  user_bin="${BATS_TEST_TMPDIR}/user-bin"
  mkdir -p "$user_bin"
  make_fake_system_shim_commands "$fake_bin"
  cat >"${user_bin}/tt-flash" <<'EOF'
#!/usr/bin/env bash
printf 'user tt-flash %s\n' "$*"
EOF
  chmod +x "${user_bin}/tt-flash"

  run env TT_INSTALL_SYSTEM_COMMAND_DIRS="$fake_bin" PATH="${user_bin}:${fake_bin}:${clean_path}" "$TT_ENV" install 2026.05.16
  [ "$status" -eq 0 ]
  [ -L "${TT_HOME}/versions/2026.05.16/bin/tt-flash" ]
  [ "$(readlink "${TT_HOME}/versions/2026.05.16/bin/tt-flash")" = "${fake_bin}/tt-flash" ]
}

@test "tt-env install ignores optional user-local tt commands" {
  fake_bin="$(make_fake_sudo)"
  clean_path="$(make_clean_path_without_system_shim_commands)"
  user_bin="${BATS_TEST_TMPDIR}/user-bin"
  mkdir -p "$user_bin"
  cat >"${user_bin}/tt-studio" <<'EOF'
#!/usr/bin/env bash
printf 'user tt-studio %s\n' "$*"
EOF
  chmod +x "${user_bin}/tt-studio"

  run env TT_INSTALL_SYSTEM_COMMAND_DIRS="$fake_bin" PATH="${user_bin}:${fake_bin}:${clean_path}" "$TT_ENV" install 2026.05.16
  [ "$status" -eq 0 ]
  [ ! -e "${TT_HOME}/versions/2026.05.16/bin/tt-studio" ]
  [[ "$output" != *"user-bin/tt-studio"* ]]
  [[ "$output" != *"[WARN] Installed command not found in PATH: tt-studio"* ]]

  run "$TT_ENV" use 2026.05.16
  [ "$status" -eq 0 ]
  run "${TT_HOME}/shims/tt-studio"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Active tt-env command not found or not executable:"* ]]
}

@test "tt-env install prefers venv command entrypoints for Python CLI packages" {
  symlinks_supported || skip "POSIX symlinks are not supported in this environment"
  fake_bin="$(make_fake_sudo)"
  clean_path="$(make_clean_path_without_system_shim_commands)"

  run env TT_FAKE_VENV_COMMANDS="tt-smi" PATH="${fake_bin}:${clean_path}" "$TT_ENV" install 2026.05.16
  [ "$status" -eq 0 ]
  [ -x "${TT_HOME}/versions/2026.05.16/bin/tt-smi" ]
  [ ! -L "${TT_HOME}/versions/2026.05.16/bin/tt-smi" ]
  grep -q 'VENV_COMMAND_NAME=tt-smi' "${TT_HOME}/versions/2026.05.16/bin/tt-smi"
  grep -q 'TARGET_COMMAND="${VENV_DIR}/bin/${VENV_COMMAND_NAME}"' "${TT_HOME}/versions/2026.05.16/bin/tt-smi"
  grep -q 'exec "$VENV_PYTHON" "$TARGET_COMMAND" "$@"' "${TT_HOME}/versions/2026.05.16/bin/tt-smi"
  grep -q "${TT_HOME}/versions/.2026.05.16.partial/venv/bin/python" "${TT_HOME}/versions/2026.05.16/venv/bin/tt-smi"
  [[ "$output" != *"[WARN] Installed command not found in PATH: tt-smi"* ]]

  ln -sf ../venv/bin/tt-smi "${TT_HOME}/versions/2026.05.16/bin/tt-smi"
  run env PATH="${fake_bin}:${clean_path}" bash -c \
    "source '${BATS_TEST_DIRNAME}/../../lib/install.sh'; parse_stack_manifest '${BATS_TEST_DIRNAME}/../../releases/2026.05.16.json'; _install_create_system_bin_links 0 '${TT_HOME}/versions/2026.05.16'"
  [ "$status" -eq 0 ]
  [ ! -L "${TT_HOME}/versions/2026.05.16/bin/tt-smi" ]
  grep -q "${TT_HOME}/versions/.2026.05.16.partial/venv/bin/python" "${TT_HOME}/versions/2026.05.16/venv/bin/tt-smi"

  run "$TT_ENV" use 2026.05.16
  [ "$status" -eq 0 ]
  run "${TT_HOME}/shims/tt-smi" probe
  [ "$status" -eq 0 ]
  [ "$output" = "venv tt-smi probe" ]
}

@test "tt-env install warns but succeeds when system package commands are absent" {
  fake_bin="$(make_fake_sudo)"
  clean_path="$(make_clean_path_without_system_shim_commands)"

  run env PATH="${fake_bin}:${clean_path}" "$TT_ENV" install 2026.05.16
  [ "$status" -eq 0 ]
  [[ "$output" == *"[WARN] Installed command not found in PATH: tt-smi"* ]]
  [[ "$output" == *"[WARN] Installed command not found in PATH: tt-flash"* ]]
  [[ "$output" == *"[WARN] Installed command not found in PATH: tt-topology"* ]]
  [[ "$output" == *"[WARN] Installed command not found in PATH: tt-burnin"* ]]
  [ -d "${TT_HOME}/versions/2026.05.16/bin" ]
  [ ! -e "${TT_HOME}/versions/2026.05.16/bin/tt-smi" ]
}

@test "tt-env install fails clearly when sudo is missing" {
  bash_env="$(make_command_absent_env sudo)"

  run env BASH_ENV="$bash_env" "$TT_ENV" install 2026.05.16
  [ "$status" -eq 1 ]
  [[ "$output" == *"sudo is required to install apt packages"* ]]
  [ ! -e "${TT_HOME}/versions/2026.05.16" ]
}

@test "tt-env install does not require add-apt-repository for official Tenstorrent repo" {
  fake_bin="$(make_fake_sudo)"
  bash_env="$(make_command_absent_env add-apt-repository)"

  run env BASH_ENV="$bash_env" PATH="${fake_bin}:${PATH}" "$TT_ENV" install 2026.05.16
  [ "$status" -eq 0 ]
  [ -d "${TT_HOME}/versions/2026.05.16" ]
}

@test "tt-env install still requires add-apt-repository for generic apt repos" {
  write_install_os_manifest "true" "https://repo.example.invalid/tenstorrent"
  fake_bin="$(make_fake_sudo)"
  bash_env="$(make_command_absent_env add-apt-repository)"

  run env BASH_ENV="$bash_env" PATH="${fake_bin}:${PATH}" "$TT_ENV" install 2026.05.16
  [ "$status" -eq 1 ]
  [[ "$output" == *"add-apt-repository is required to add repositories"* ]]
  [ ! -e "${TT_HOME}/versions/2026.05.16" ]
}

@test "tt-env install --dry-run reports apt actions without sudo" {
  bash_env="$(make_command_absent_env sudo)"
  clean_path="$(make_clean_path_without_system_shim_commands)"

  run env BASH_ENV="$bash_env" PATH="$clean_path" "$TT_ENV" install --dry-run 2026.05.16
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] Would create apt keyring directory: /etc/apt/keyrings"* ]]
  [[ "$output" == *"[dry-run] Would download Tenstorrent apt signing key: https://ppa.tenstorrent.com/tt-pkg-key.asc"* ]]
  [[ "$output" == *"[dry-run] Would verify Tenstorrent apt signing key fingerprint: 58540CD771C55DD7C33030CA8A9D565F6A208463"* ]]
  [[ "$output" == *"[dry-run] Would write apt source /etc/apt/sources.list.d/tenstorrent.list: deb [arch=amd64 signed-by=/etc/apt/keyrings/tt-pkg-key.asc] https://ppa.tenstorrent.com/ubuntu/ jammy main"* ]]
  [[ "$output" == *"[dry-run] Would install apt packages: cmake ninja-build zlib1g-dev tenstorrent-dkms=2.8.0 tt-smi=5.0.1 tt-flash=3.6.5 tt-topology=1.2.19 tt-burnin=0.4.0"* ]]
  [[ "$output" == *"[dry-run] Would create Python virtualenv: ${TT_HOME}/versions/2026.05.16/venv"* ]]
  [[ "$output" == *"[dry-run] Would install pip packages into ${TT_HOME}/versions/2026.05.16/venv:"* ]]
  for package_pin in "tt-smi==5.2.0" "tt-umd==0.9.5" "textual==0.59.0" "elasticsearch==8.11.0"; do
    [[ "$output" == *"$package_pin"* ]]
  done
  [[ "$output" == *"[dry-run] Would use venv command if installed: ${TT_HOME}/versions/2026.05.16/venv/bin/tt-smi"* ]]
  [[ "$output" == *"[dry-run] Would create Python virtualenv wrapper for tt-smi after system package install."* ]]
  [[ "$output" == *"[dry-run] Would create bin link for tt-flash after system package install."* ]]
  [[ "$output" == *"[dry-run] Would create bin link for tt-topology after system package install."* ]]
  [[ "$output" == *"[dry-run] Would create bin link for tt-burnin after system package install."* ]]
  [ ! -e "${TT_HOME}/versions/2026.05.16" ]
}

@test "tt-env install fails clearly when python3 is missing" {
  fake_bin="$(make_fake_sudo)"
  bash_env="$(make_command_absent_env python3)"

  run env BASH_ENV="$bash_env" PATH="${fake_bin}:${PATH}" "$TT_ENV" install 2026.05.16
  [ "$status" -eq 1 ]
  [[ "$output" == *"python3 is required to create a virtualenv for Python packages:"* ]]
  for package_pin in "tt-smi==5.2.0" "tt-umd==0.9.5" "textual==0.59.0" "elasticsearch==8.11.0"; do
    [[ "$output" == *"$package_pin"* ]]
  done
  [ ! -e "${TT_HOME}/versions/2026.05.16" ]
  [ ! -e "${TT_HOME}/versions/.2026.05.16.partial" ]
}

@test "tt-env install fails clearly when Python package pins are missing" {
  fake_bin="$(make_fake_sudo)"
  mkdir -p "${TT_HOME}/releases"
  cat >"${TT_HOME}/releases/2026.05.16.json" <<'EOF'
{
  "release": "2026.05.16",
  "components": {
    "tt-kmd": "ttkmd-2.8.0",
    "tt-smi": "v5.2.0",
    "firmware": "v19.6.0",
    "tt-metal": "v0.70.1"
  },
  "system_packages": {
    "kmd": "2.8.0",
    "smi": "5.0.1",
    "flash": "3.6.5",
    "topology": "1.2.19",
    "burnin": "0.4.0"
  }
}
EOF

  run env PATH="${fake_bin}:${PATH}" "$TT_ENV" install 2026.05.16
  [ "$status" -eq 1 ]
  [[ "$output" == *"Stack manifest is missing Python package version: python_packages.tt-smi"* ]]
  [ ! -e "${TT_HOME}/versions/2026.05.16" ]
  [ ! -e "${TT_HOME}/versions/.2026.05.16.partial" ]
}

@test "repository apt manifests use official Tenstorrent repo" {
  repo_dir="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  fake_bin="$(make_fake_sudo)"
  mkdir -p "${TT_HOME}/manifests" "${TT_HOME}/releases"
  cp "${repo_dir}/manifests/ubuntu-22.04.env" "${TT_HOME}/manifests/ubuntu-22.04.env"
  cp "${repo_dir}/releases/2026.05.16.json" "${TT_HOME}/releases/2026.05.16.json"

  run env PATH="${fake_bin}:${PATH}" "$TT_ENV" install 2026.05.16
  [ "$status" -eq 0 ]
  [ -d "${TT_HOME}/versions/2026.05.16" ]
  mapfile -t apt_calls <"$TT_APT_LOG"
  [ "${apt_calls[0]}" = "install -d -m 0755 /etc/apt/keyrings" ]
  [[ "${apt_calls[1]}" == install\ -m\ 0644\ *\ /etc/apt/keyrings/tt-pkg-key.asc ]]
  [ "${apt_calls[4]}" = "apt-get install -y cmake ninja-build zlib1g-dev tenstorrent-dkms=2.8.0 tt-smi=5.0.1 tt-flash=3.6.5 tt-topology=1.2.19 tt-burnin=0.4.0" ]
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
VIRT_PKG_SMI="tt-smi-24"
VIRT_PKG_FLASH="tt-flash-24"
VIRT_PKG_TOPOLOGY="tt-topology-24"
VIRT_PKG_BURNIN="tt-burnin-24"
WORKAROUNDS=()
EOF
  bash_env="$(make_command_absent_env sudo)"

  run env BASH_ENV="$bash_env" TT_OVERRIDE_OS_ID=ubuntu TT_OVERRIDE_OS_VERSION=24.04 \
    "$TT_ENV" install --dry-run 2026.05.16
  [ "$status" -eq 0 ]
  [[ "$output" == *"Using override OS: ubuntu 24.04"* ]]
  [[ "$output" == *"[dry-run] Would install apt packages: cmake-24 ninja-build-24 zlib1g-dev-24 tenstorrent-dkms-24=2.8.0 tt-smi-24=5.0.1 tt-flash-24=3.6.5 tt-topology-24=1.2.19 tt-burnin-24=0.4.0"* ]]
  [ ! -e "${TT_HOME}/versions/2026.05.16" ]
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
VIRT_PKG_SMI="tt-smi-mint"
VIRT_PKG_FLASH="tt-flash-mint"
VIRT_PKG_TOPOLOGY="tt-topology-mint"
VIRT_PKG_BURNIN="tt-burnin-mint"
WORKAROUNDS=()
EOF
  bash_env="$(make_command_absent_env sudo)"

  run env BASH_ENV="$bash_env" TT_OVERRIDE_OS_ID=linuxmint TT_OVERRIDE_OS_VERSION=22.1 \
    "$TT_ENV" install --dry-run 2026.05.16
  [ "$status" -eq 0 ]
  [[ "$output" == *"Using override OS: linuxmint 22.1"* ]]
  [[ "$output" == *"[dry-run] Would install apt packages: cmake-mint ninja-build-mint zlib1g-dev-mint tenstorrent-dkms-mint=2.8.0 tt-smi-mint=5.0.1 tt-flash-mint=3.6.5 tt-topology-mint=1.2.19 tt-burnin-mint=0.4.0"* ]]
  [ ! -e "${TT_HOME}/versions/2026.05.16" ]
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
VIRT_PKG_SMI="tt-smi-mint"
VIRT_PKG_FLASH="tt-flash-mint"
VIRT_PKG_TOPOLOGY="tt-topology-mint"
VIRT_PKG_BURNIN="tt-burnin-mint"
WORKAROUNDS=()
EOF
  bash_env="$(make_command_absent_env sudo)"

  run env BASH_ENV="$bash_env" TT_OVERRIDE_OS_ID=linuxmint TT_OVERRIDE_OS_VERSION=22.1 \
    "$TT_ENV" install --dry-run 2026.05.16
  [ "$status" -eq 0 ]
  [[ "$output" == *"deb [arch=amd64 signed-by=/etc/apt/keyrings/tt-pkg-key.asc] https://ppa.tenstorrent.com/ubuntu/ noble main"* ]]
  [ ! -e "${TT_HOME}/versions/2026.05.16" ]
}

@test "tt-env install fails before apt mutation for unsupported Tenstorrent repo codename" {
  write_test_os_release ubuntu "26.04" resolute ""
  fake_bin="$(make_fake_sudo)"

  run env PATH="${fake_bin}:${PATH}" "$TT_ENV" install 2026.05.16
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unsupported Tenstorrent apt repository codename 'resolute'"* ]]
  [ ! -e "${TT_HOME}/versions/2026.05.16" ]
  [ ! -s "$TT_APT_LOG" ]
}

@test "tt-env install fails before apt mutation when curl is missing for official repo" {
  fake_bin="$(make_fake_sudo)"
  bash_env="$(make_command_absent_env curl)"

  run env BASH_ENV="$bash_env" PATH="${fake_bin}:${PATH}" "$TT_ENV" install 2026.05.16
  [ "$status" -eq 1 ]
  [[ "$output" == *"curl is required to download the Tenstorrent apt signing key"* ]]
  [ ! -e "${TT_HOME}/versions/2026.05.16" ]
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

  run env PATH="${fake_bin}:${PATH}" "$TT_ENV" install 2026.05.16
  [ "$status" -eq 1 ]
  [[ "$output" == *"Tenstorrent apt signing key fingerprint mismatch"* ]]
  [ ! -e "${TT_HOME}/versions/2026.05.16" ]
  [ ! -s "$TT_APT_LOG" ]
}
