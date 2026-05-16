#!/usr/bin/env bats

setup() {
  TT_ENV="${BATS_TEST_DIRNAME}/../../bin/tt-env"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export TT_HOME="${BATS_TEST_TMPDIR}/tt-home"
}

make_installed_release() {
  local release="$1"
  local version_dir="${TT_HOME}/versions/${release}"

  mkdir -p "${version_dir}/bin"
  printf 'release=%s\n' "$release" >"${version_dir}/.tt-env-installed"
}

symlinks_supported() {
  local probe_dir="${BATS_TEST_TMPDIR}/symlink-probe"

  rm -rf "$probe_dir"
  mkdir -p "${probe_dir}/target"
  ln -sfn "${probe_dir}/target" "${probe_dir}/link" 2>/dev/null
  [ -L "${probe_dir}/link" ]
}

@test "tt-env remove deletes an installed release directory" {
  make_installed_release "2026.05.16"

  run "$TT_ENV" remove 2026.05.16

  [ "$status" -eq 0 ]
  [ ! -e "${TT_HOME}/versions/2026.05.16" ]
  [[ "$output" == *"Removed release 2026.05.16"* ]]
}

@test "tt-env remove clears current symlink when removing active release" {
  symlinks_supported || skip "POSIX symlinks are not supported in this environment"
  make_installed_release "2026.05.16"
  ln -sfn "${TT_HOME}/versions/2026.05.16" "${TT_HOME}/current"

  run "$TT_ENV" remove 2026.05.16

  [ "$status" -eq 0 ]
  [ ! -e "${TT_HOME}/current" ]
}

@test "tt-env remove fails for an uninstalled release" {
  run "$TT_ENV" remove 2099.9

  [ "$status" -eq 1 ]
  [[ "$output" == *"Release 2099.9 is not installed"* ]]
}

@test "tt-env remove refuses an unmarked version directory" {
  mkdir -p "${TT_HOME}/versions/2026.05.16"

  run "$TT_ENV" remove 2026.05.16

  [ "$status" -eq 1 ]
  [[ "$output" == *"Release 2026.05.16 is not installed"* ]]
}
