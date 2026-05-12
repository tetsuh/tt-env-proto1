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

make_fake_non_symlink_ln() {
  local fake_bin="${BATS_TEST_TMPDIR}/fake-ln-bin"

  mkdir -p "$fake_bin"
  cat >"${fake_bin}/ln" <<'EOF'
#!/usr/bin/env bash
dest=""
for arg in "$@"; do
  dest="$arg"
done
mkdir -p "$dest"
EOF
  chmod +x "${fake_bin}/ln"
  printf '%s\n' "$fake_bin"
}

@test "tt-env use switches current symlink between installed releases" {
  symlinks_supported || skip "POSIX symlinks are not supported in this environment"
  make_installed_release "2024.1"
  make_installed_release "2024.2"

  run "$TT_ENV" use 2024.1
  [ "$status" -eq 0 ]
  [ -L "${TT_HOME}/current" ]
  [ "$(readlink "${TT_HOME}/current")" = "${TT_HOME}/versions/2024.1" ]
  [[ "$output" == *"Using release 2024.1"* ]]

  run "$TT_ENV" use 2024.2
  [ "$status" -eq 0 ]
  [ -L "${TT_HOME}/current" ]
  [ "$(readlink "${TT_HOME}/current")" = "${TT_HOME}/versions/2024.2" ]
  [[ "$output" == *"Using release 2024.2"* ]]
}

@test "tt-env use fails clearly when ln does not create a symlink" {
  make_installed_release "2024.1"
  fake_bin="$(make_fake_non_symlink_ln)"

  run env PATH="${fake_bin}:${PATH}" "$TT_ENV" use 2024.1

  [ "$status" -eq 1 ]
  [[ "$output" == *"ln -sfn did not create a symlink"* ]]
  [ ! -e "${TT_HOME}/current" ]
}

@test "tt-env use fails for an uninstalled release" {
  run "$TT_ENV" use 2099.9

  [ "$status" -eq 1 ]
  [[ "$output" == *"Release 2099.9 is not installed"* ]]
  [ ! -e "${TT_HOME}/current" ]
}

@test "tt-env use refuses an unmarked version directory" {
  mkdir -p "${TT_HOME}/versions/2024.1"

  run "$TT_ENV" use 2024.1

  [ "$status" -eq 1 ]
  [[ "$output" == *"Release 2024.1 is not installed"* ]]
  [ ! -e "${TT_HOME}/current" ]
}

@test "tt-env use refuses to replace a non-symlink current path" {
  make_installed_release "2024.1"
  mkdir -p "${TT_HOME}/current"

  run "$TT_ENV" use 2024.1

  [ "$status" -eq 1 ]
  [[ "$output" == *"Refusing to replace non-symlink current path"* ]]
}
