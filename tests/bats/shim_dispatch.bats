#!/usr/bin/env bats

setup() {
  REPO_DIR="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  INSTALL_SH="${REPO_DIR}/install.sh"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export TT_HOME="${BATS_TEST_TMPDIR}/tt-home"
}

symlinks_supported() {
  local probe_dir="${BATS_TEST_TMPDIR}/symlink-probe"

  rm -rf "$probe_dir"
  mkdir -p "${probe_dir}/target"
  ln -sfn "${probe_dir}/target" "${probe_dir}/link" 2>/dev/null
  [ -L "${probe_dir}/link" ]
}

make_mock_release() {
  local release="$1"
  local version_dir="${TT_HOME}/versions/${release}"

  mkdir -p "${version_dir}/bin"
  cat >"${version_dir}/bin/tt-smi" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "--version" ]]; then
  printf 'tt-smi ${release}\n'
else
  printf 'mock tt-smi ${release}: %s\n' "\$*"
fi
EOF
  chmod +x "${version_dir}/bin/tt-smi"
  printf 'release=%s\n' "$release" >"${version_dir}/.tt-env-installed"
}

@test "tt-smi shim dispatch follows the active release" {
  symlinks_supported || skip "POSIX symlinks are not supported in this environment"

  run bash "$INSTALL_SH"
  [ "$status" -eq 0 ]

  make_mock_release "2024.1"
  make_mock_release "2024.2"

  run "${TT_HOME}/bin/tt-env" use 2024.1
  [ "$status" -eq 0 ]

  run "${TT_HOME}/shims/tt-smi" --version
  [ "$status" -eq 0 ]
  [ "$output" = "tt-smi 2024.1" ]

  run "${TT_HOME}/bin/tt-env" use 2024.2
  [ "$status" -eq 0 ]

  run "${TT_HOME}/shims/tt-smi" --version
  [ "$status" -eq 0 ]
  [ "$output" = "tt-smi 2024.2" ]
}
