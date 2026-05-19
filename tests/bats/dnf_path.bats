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
VIRT_PKG_BURNIN="tt-burnin"
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
  cat >"${fake_bin}/python3" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-m" && "${2:-}" == "venv" && -n "${3:-}" ]]; then
  venv_dir="$3"
  printf 'venv %s\n' "$venv_dir" >>"$TT_PIP_LOG"
  mkdir -p "${venv_dir}/bin"
  cat >"${venv_dir}/bin/python" <<'PYEOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-m" && "${2:-}" == "pip" && "${3:-}" == "install" ]]; then
  printf '%s\n' "$*" >>"$TT_PIP_LOG"
  exit 0
fi
printf 'venv python %s\n' "$*" >>"$TT_PIP_LOG"
PYEOF
  chmod +x "${venv_dir}/bin/python"
  exit 0
fi
printf 'python3 %s\n' "$*" >>"$TT_PIP_LOG"
EOF
  touch "${fake_bin}/dnf"
  chmod +x "${fake_bin}/sudo" "${fake_bin}/python3" "${fake_bin}/dnf"
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
  [ "${dnf_calls[2]}" = "dnf install -y cmake ninja-build zlib-devel tenstorrent-dkms-2.8.0 tt-smi-5.0.1 tt-flash-3.6.5 tt-topology-1.2.19 tt-burnin-0.4.0" ]
  mapfile -t pip_calls <"$TT_PIP_LOG"
  [[ "${pip_calls[0]}" == venv\ */versions/.2026.05.16.partial/venv ]]
  [[ "${pip_calls[1]}" == -m\ pip\ install\ --disable-pip-version-check* ]]
  for package_pin in "tt-smi==5.2.0" "tt-umd==0.9.5" "textual==0.59.0" "elasticsearch==8.11.0"; do
    [[ "${pip_calls[1]}" == *"$package_pin"* ]]
  done
}
