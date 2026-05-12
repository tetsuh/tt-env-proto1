#!/usr/bin/env bats

setup() {
  TT_ENV="${BATS_TEST_DIRNAME}/../../bin/tt-env"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export TT_HOME="${BATS_TEST_TMPDIR}/tt-home"
  export TT_STATUS_LSPCI_FIXTURE="${BATS_TEST_TMPDIR}/lspci-empty.txt"
}

make_fake_status_kmd_tools() {
  local fake_bin="${BATS_TEST_TMPDIR}/fake-status-kmd-bin"

  mkdir -p "$fake_bin"
  cat >"${fake_bin}/lspci" <<'EOF'
#!/usr/bin/env bash
cat "${TT_STATUS_LSPCI_FIXTURE}"
EOF
  cat >"${fake_bin}/modinfo" <<'EOF'
#!/usr/bin/env bash
if [[ "${TT_STATUS_MODINFO_MODE:-loaded}" = "unloaded" ]]; then
  exit 1
fi
if [[ "$1" = "-F" && "$2" = "version" && "$3" = "tenstorrent" ]]; then
  printf '1.2.3\n'
  exit 0
fi
exit 2
EOF
  chmod +x "${fake_bin}/lspci" "${fake_bin}/modinfo"
  printf '%s\n' "$fake_bin"
}

@test "tt-env status prints loaded KMD module version" {
  fake_bin="$(make_fake_status_kmd_tools)"
  printf '%s\n' "" >"$TT_STATUS_LSPCI_FIXTURE"

  PATH="${fake_bin}:${PATH}" run "$TT_ENV" status

  [ "$status" -eq 0 ]
  [[ "$output" == *"KMD module version: 1.2.3"* ]]
}

@test "tt-env status prints not loaded when KMD module version is unavailable" {
  fake_bin="$(make_fake_status_kmd_tools)"
  printf '%s\n' "" >"$TT_STATUS_LSPCI_FIXTURE"

  PATH="${fake_bin}:${PATH}" TT_STATUS_MODINFO_MODE=unloaded run "$TT_ENV" status

  [ "$status" -eq 0 ]
  [[ "$output" == *"KMD module version: (not loaded)"* ]]
}
