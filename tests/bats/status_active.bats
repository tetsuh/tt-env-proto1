#!/usr/bin/env bats

setup() {
  TT_ENV="${BATS_TEST_DIRNAME}/../../bin/tt-env"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export TT_HOME="${BATS_TEST_TMPDIR}/tt-home"
  export TT_STATUS_LSPCI_FIXTURE="${BATS_TEST_TMPDIR}/lspci-empty.txt"
}

make_fake_lspci() {
  local fake_bin="${BATS_TEST_TMPDIR}/fake-status-active-bin"

  mkdir -p "$fake_bin"
  cat >"${fake_bin}/lspci" <<'EOF'
#!/usr/bin/env bash
cat "${TT_STATUS_LSPCI_FIXTURE}"
EOF
  cat >"${fake_bin}/modinfo" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "${fake_bin}/lspci" "${fake_bin}/modinfo"
  printf '%s\n' "$fake_bin"
}

symlinks_supported() {
  local probe_dir="${BATS_TEST_TMPDIR}/symlink-probe"

  rm -rf "$probe_dir"
  mkdir -p "${probe_dir}/target"
  ln -sfn "${probe_dir}/target" "${probe_dir}/link" 2>/dev/null
  [ -L "${probe_dir}/link" ]
}

@test "tt-env status prints none when no release is active" {
  fake_bin="$(make_fake_lspci)"
  printf '%s\n' "" >"$TT_STATUS_LSPCI_FIXTURE"

  PATH="${fake_bin}:${PATH}" run "$TT_ENV" status

  [ "$status" -eq 0 ]
  [[ "$output" == *"Active release: (none)"* ]]
}

@test "tt-env status prints active release id from current symlink" {
  symlinks_supported || skip "POSIX symlinks are not supported in this environment"
  fake_bin="$(make_fake_lspci)"
  release_dir="${TT_HOME}/versions/2026.05.16"
  mkdir -p "$release_dir"
  ln -sfn "$release_dir" "${TT_HOME}/current"
  printf '%s\n' "" >"$TT_STATUS_LSPCI_FIXTURE"

  PATH="${fake_bin}:${PATH}" run "$TT_ENV" status

  [ "$status" -eq 0 ]
  [[ "$output" == *"Active release: 2026.05.16"* ]]
}

@test "tt-env status strips trailing slash from current symlink target" {
  symlinks_supported || skip "POSIX symlinks are not supported in this environment"
  fake_bin="$(make_fake_lspci)"
  release_dir="${TT_HOME}/versions/2026.05.16"
  mkdir -p "$release_dir"
  ln -sfn "${release_dir}/" "${TT_HOME}/current"
  printf '%s\n' "" >"$TT_STATUS_LSPCI_FIXTURE"

  PATH="${fake_bin}:${PATH}" run "$TT_ENV" status

  [ "$status" -eq 0 ]
  [[ "$output" == *"Active release: 2026.05.16"* ]]
}
