#!/usr/bin/env bats

setup() {
  TT_ENV="${BATS_TEST_DIRNAME}/../../bin/tt-env"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export TT_HOME="${BATS_TEST_TMPDIR}/tt-home"
  export TT_OVERRIDE_OS_ID="ubuntu"
  export TT_OVERRIDE_OS_VERSION="22.04"
  export TT_APT_LOG="${BATS_TEST_TMPDIR}/apt.log"

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
  fake_bin="${BATS_TEST_TMPDIR}/fake-bin"
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

@test "tt-env install adds required repos before apt install" {
  fake_bin="$(make_fake_sudo)"

  run env PATH="${fake_bin}:${PATH}" "$TT_ENV" install 2024.1
  [ "$status" -eq 0 ]
  [ -d "${TT_HOME}/versions/2024.1" ]

  mapfile -t apt_calls <"$TT_APT_LOG"
  [ "${apt_calls[0]}" = "add-apt-repository -y ppa:tenstorrent/ppa" ]
  [ "${apt_calls[1]}" = "apt-get update" ]
  [ "${apt_calls[2]}" = "apt-get install -y cmake ninja-build zlib1g-dev tt-kmd-dkms" ]
}

@test "tt-env install fails clearly when sudo is missing" {
  bash_env="$(make_command_absent_env sudo)"

  run env BASH_ENV="$bash_env" "$TT_ENV" install 2024.1
  [ "$status" -eq 1 ]
  [[ "$output" == *"sudo is required to install apt packages"* ]]
  [ ! -e "${TT_HOME}/versions/2024.1" ]
}

@test "tt-env install fails clearly when add-apt-repository is missing" {
  fake_bin="$(make_fake_sudo)"
  bash_env="$(make_command_absent_env add-apt-repository)"

  run env BASH_ENV="$bash_env" PATH="${fake_bin}:${PATH}" "$TT_ENV" install 2024.1
  [ "$status" -eq 1 ]
  [[ "$output" == *"add-apt-repository is required to add repositories"* ]]
  [ ! -e "${TT_HOME}/versions/2024.1" ]
}

@test "tt-env install --dry-run reports apt actions without sudo" {
  bash_env="$(make_command_absent_env sudo)"

  run env BASH_ENV="$bash_env" "$TT_ENV" install --dry-run 2024.1
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] Would add apt repository: ppa:tenstorrent/ppa"* ]]
  [[ "$output" == *"[dry-run] Would install apt packages: cmake ninja-build zlib1g-dev tt-kmd-dkms"* ]]
  [ ! -e "${TT_HOME}/versions/2024.1" ]
}
