#!/usr/bin/env bats

setup() {
  REPO_DIR="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  INSTALL_SH="${REPO_DIR}/install.sh"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export TT_HOME="${BATS_TEST_TMPDIR}/tt-home"
}

assert_installed_layout() {
  for subdir in bin lib manifests releases versions shims; do
    [ -d "${TT_HOME}/${subdir}" ]
  done

  [ -x "${TT_HOME}/bin/tt-env" ]
  [ -f "${TT_HOME}/lib/core.sh" ]
  [ -f "${TT_HOME}/lib/install.sh" ]
  [ -f "${TT_HOME}/lib/security.sh" ]
  [ -f "${TT_HOME}/lib/shims.sh" ]
  [ -f "${TT_HOME}/lib/version_manager.sh" ]
  [ -f "${TT_HOME}/manifests/ubuntu-22.04.env" ]
  [ -f "${TT_HOME}/releases/2024.1.json" ]
  [ -f "${TT_HOME}/VERSION" ]
  [ -x "${TT_HOME}/shims/tt-smi" ]
}

@test "install.sh installs tt-env and --version works on PATH" {
  run bash "$INSTALL_SH"
  [ "$status" -eq 0 ]
  assert_installed_layout
  [[ "$output" == *"export PATH=\"${TT_HOME}/shims:${TT_HOME}/bin:\$PATH\""* ]]
  [[ "$output" == *"fish_add_path \"${TT_HOME}/shims\" \"${TT_HOME}/bin\""* ]]
  [[ "$output" == *"tt-env install --help"* ]]

  PATH="${TT_HOME}/bin:${PATH}" run tt-env --version
  [ "$status" -eq 0 ]
  [ "$output" = "$(cat "${REPO_DIR}/VERSION")" ]
}

@test "install.sh is idempotent" {
  run bash "$INSTALL_SH"
  [ "$status" -eq 0 ]

  run bash "$INSTALL_SH"
  [ "$status" -eq 0 ]
  assert_installed_layout
}

@test "install.sh validates source files before creating TT_HOME" {
  broken_repo="${BATS_TEST_TMPDIR}/broken-repo"
  mkdir -p "$broken_repo"
  cp "$INSTALL_SH" "${broken_repo}/install.sh"
  chmod +x "${broken_repo}/install.sh"

  run bash "${broken_repo}/install.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Missing ${broken_repo}/bin/tt-env"* ]]
  [ ! -e "$TT_HOME" ]
}
