#!/usr/bin/env bats

setup() {
  TT_ENV="${BATS_TEST_DIRNAME}/../../bin/tt-env"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export TT_HOME="${BATS_TEST_TMPDIR}/tt-home"
}

make_fake_status_tools() {
  local fake_bin="${BATS_TEST_TMPDIR}/fake-status-bin"

  mkdir -p "$fake_bin"
  cat >"${fake_bin}/lspci" <<'EOF'
#!/usr/bin/env bash
cat "${TT_STATUS_LSPCI_FIXTURE}"
EOF
  chmod +x "${fake_bin}/lspci"
  printf '%s\n' "$fake_bin"
}

@test "tt-env status prints zero devices when Tenstorrent hardware is absent" {
  fake_bin="$(make_fake_status_tools)"
  export TT_STATUS_LSPCI_FIXTURE="${BATS_TEST_TMPDIR}/lspci-none.txt"
  cat >"$TT_STATUS_LSPCI_FIXTURE" <<'EOF'
0000:00:1f.0 ISA bridge [0601]: Intel Corporation Device [8086:7a04]
EOF

  PATH="${fake_bin}:${PATH}" run "$TT_ENV" status

  [ "$status" -eq 0 ]
  [[ "$output" == *"Status"* ]]
  [[ "$output" == *"Tenstorrent hardware: 0 device(s)"* ]]
  [[ "$output" != *"not implemented yet"* ]]
}

@test "tt-env status prints mocked Tenstorrent hardware devices" {
  fake_bin="$(make_fake_status_tools)"
  export TT_STATUS_LSPCI_FIXTURE="${BATS_TEST_TMPDIR}/lspci-tt.txt"
  cat >"$TT_STATUS_LSPCI_FIXTURE" <<'EOF'
0000:00:1f.0 ISA bridge [0601]: Intel Corporation Device [8086:7a04]
0000:01:00.0 Processing accelerators [1200]: Tenstorrent Inc Grayskull [1e52:faca]
0000:02:00.0 Processing accelerators [1200]: Tenstorrent Inc Wormhole [1e52:401e]
EOF

  PATH="${fake_bin}:${PATH}" run "$TT_ENV" status

  [ "$status" -eq 0 ]
  [[ "$output" == *"Tenstorrent hardware: 2 device(s)"* ]]
  [[ "$output" == *"0000:01:00.0"* ]]
  [[ "$output" == *"Grayskull"* ]]
  [[ "$output" == *"0000:02:00.0"* ]]
  [[ "$output" == *"Wormhole"* ]]
  [[ "$output" != *"Intel Corporation"* ]]
}

@test "tt-env status fails clearly when lspci is missing" {
  fake_bin="${BATS_TEST_TMPDIR}/path-without-lspci"
  mkdir -p "$fake_bin"
  for command in bash dirname mkdir; do
    cat >"${fake_bin}/${command}" <<EOF
#!/usr/bin/bash
exec /usr/bin/${command} "\$@"
EOF
    chmod +x "${fake_bin}/${command}"
  done

  PATH="$fake_bin" run "$TT_ENV" status

  [ "$status" -eq 1 ]
  [[ "$output" == *"lspci is required to detect Tenstorrent hardware"* ]]
  [[ "$output" != *"Tenstorrent hardware: 0 device(s)"* ]]
}
