#!/usr/bin/env bats

setup() {
  REPO_DIR="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export TT_HOME="${BATS_TEST_TMPDIR}/tt-home"
  export TT_KMD_LOG="${BATS_TEST_TMPDIR}/kmd.log"
  export TT_MODPROBE_MARKER="${BATS_TEST_TMPDIR}/tenstorrent.loaded"
  source "${REPO_DIR}/lib/kmd.sh"
}

make_fake_kmd_tools() {
  local fake_bin="${BATS_TEST_TMPDIR}/fake-kmd-bin"

  mkdir -p "$fake_bin"
  cat >"${fake_bin}/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >>"$TT_KMD_LOG"
"$@"
EOF
  cat >"${fake_bin}/apt-get" <<'EOF'
#!/usr/bin/env bash
printf 'apt-get %s\n' "$*" >>"$TT_KMD_LOG"
EOF
  cat >"${fake_bin}/modprobe" <<'EOF'
#!/usr/bin/env bash
printf 'modprobe %s\n' "$*" >>"$TT_KMD_LOG"
printf '%s\n' "$1" >"$TT_MODPROBE_MARKER"
EOF
  chmod +x "${fake_bin}/sudo" "${fake_bin}/apt-get" "${fake_bin}/modprobe"
  printf '%s\n' "$fake_bin"
}

make_fake_kmd_tools_without_sudo() {
  local fake_bin="${BATS_TEST_TMPDIR}/fake-kmd-no-sudo-bin"

  mkdir -p "$fake_bin"
  cat >"${fake_bin}/apt-get" <<'EOF'
#!/usr/bin/env bash
EOF
  cat >"${fake_bin}/modprobe" <<'EOF'
#!/usr/bin/env bash
EOF
  chmod +x "${fake_bin}/apt-get" "${fake_bin}/modprobe"
  printf '%s\n' "$fake_bin"
}

@test "kmd_install installs tt-kmd-dkms and loads tenstorrent module" {
  fake_bin="$(make_fake_kmd_tools)"

  PATH="${fake_bin}:${PATH}" run kmd_install

  [ "$status" -eq 0 ]
  [ -f "$TT_MODPROBE_MARKER" ]
  mapfile -t calls <"$TT_KMD_LOG"
  [ "${calls[0]}" = "sudo apt-get install -y tt-kmd-dkms" ]
  [ "${calls[1]}" = "apt-get install -y tt-kmd-dkms" ]
  [ "${calls[2]}" = "sudo modprobe tenstorrent" ]
  [ "${calls[3]}" = "modprobe tenstorrent" ]
  [[ "$output" == *"tenstorrent KMD module is loaded"* ]]
}

@test "kmd_install accepts an explicit package name" {
  fake_bin="$(make_fake_kmd_tools)"

  PATH="${fake_bin}:${PATH}" run kmd_install custom-kmd-dkms

  [ "$status" -eq 0 ]
  grep -q "apt-get install -y custom-kmd-dkms" "$TT_KMD_LOG"
}

@test "kmd_install accepts an overridden module name" {
  fake_bin="$(make_fake_kmd_tools)"

  PATH="${fake_bin}:${PATH}" TT_KMD_MODULE="custom_tenstorrent" run kmd_install

  [ "$status" -eq 0 ]
  [ "$(cat "$TT_MODPROBE_MARKER")" = "custom_tenstorrent" ]
  grep -q "modprobe custom_tenstorrent" "$TT_KMD_LOG"
  [[ "$output" == *"custom_tenstorrent KMD module is loaded"* ]]
}

@test "kmd_install fails clearly when sudo is missing" {
  fake_bin="$(make_fake_kmd_tools_without_sudo)"

  PATH="$fake_bin" run kmd_install

  [ "$status" -eq 1 ]
  [[ "$output" == *"sudo is required to install and load the KMD"* ]]
}

@test "kmd_install fails when apt-get install fails" {
  fake_bin="$(make_fake_kmd_tools)"
  cat >"${fake_bin}/apt-get" <<'EOF'
#!/usr/bin/env bash
printf 'apt-get %s\n' "$*" >>"$TT_KMD_LOG"
exit 42
EOF
  chmod +x "${fake_bin}/apt-get"

  PATH="${fake_bin}:${PATH}" run kmd_install

  [ "$status" -eq 1 ]
  [[ "$output" == *"Failed to install KMD package"* ]]
  [ ! -f "$TT_MODPROBE_MARKER" ]
}

@test "kmd_install fails when modprobe fails" {
  fake_bin="$(make_fake_kmd_tools)"
  cat >"${fake_bin}/modprobe" <<'EOF'
#!/usr/bin/env bash
printf 'modprobe %s\n' "$*" >>"$TT_KMD_LOG"
exit 43
EOF
  chmod +x "${fake_bin}/modprobe"

  PATH="${fake_bin}:${PATH}" run kmd_install

  [ "$status" -eq 1 ]
  [[ "$output" == *"Failed to load tenstorrent KMD module"* ]]
  [ ! -f "$TT_MODPROBE_MARKER" ]
}
