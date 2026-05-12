#!/usr/bin/env bats

setup() {
  REPO_DIR="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export TT_HOME="${BATS_TEST_TMPDIR}/tt-home"
  export TT_KMD_LOG="${BATS_TEST_TMPDIR}/kmd-swap.log"
  export TT_KMD_LOADED_MARKER="${BATS_TEST_TMPDIR}/tenstorrent.loaded"
  export TT_KMD_MODPROBE_COUNT="${BATS_TEST_TMPDIR}/modprobe.count"
  export TT_KMD_DEVICE_GLOB="${BATS_TEST_TMPDIR}/dev/tenstorrent/*"
  source "${REPO_DIR}/lib/kmd.sh"
}

make_fake_swap_tools() {
  local fake_bin="${BATS_TEST_TMPDIR}/fake-swap-bin"

  mkdir -p "$fake_bin"
  cat >"${fake_bin}/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >>"$TT_KMD_LOG"
"$@"
EOF
  cat >"${fake_bin}/lsmod" <<'EOF'
#!/usr/bin/env bash
printf 'Module Size Used by\n'
if [[ -f "$TT_KMD_LOADED_MARKER" ]]; then
  printf 'tenstorrent 12345 0\n'
fi
EOF
  cat >"${fake_bin}/rmmod" <<'EOF'
#!/usr/bin/env bash
printf 'rmmod %s\n' "$*" >>"$TT_KMD_LOG"
rm -f "$TT_KMD_LOADED_MARKER"
EOF
  cat >"${fake_bin}/modprobe" <<'EOF'
#!/usr/bin/env bash
count=0
if [[ -f "$TT_KMD_MODPROBE_COUNT" ]]; then
  count="$(cat "$TT_KMD_MODPROBE_COUNT")"
fi
count=$((count + 1))
printf '%s\n' "$count" >"$TT_KMD_MODPROBE_COUNT"
printf 'modprobe %s\n' "$*" >>"$TT_KMD_LOG"
if [[ -n "${TT_KMD_FAIL_FIRST_MODPROBE:-}" && "$count" -eq 1 ]]; then
  exit 43
fi
printf '%s\n' "$1" >"$TT_KMD_LOADED_MARKER"
EOF
  cat >"${fake_bin}/mokutil" <<'EOF'
#!/usr/bin/env bash
printf 'SecureBoot disabled\n'
EOF
  chmod +x "${fake_bin}/sudo" "${fake_bin}/lsmod" "${fake_bin}/rmmod" \
    "${fake_bin}/modprobe" "${fake_bin}/mokutil"
  printf '%s\n' "$fake_bin"
}

make_loaded_module() {
  printf 'tenstorrent\n' >"$TT_KMD_LOADED_MARKER"
}

@test "kmd_swap unloads the current module and loads it again" {
  fake_bin="$(make_fake_swap_tools)"
  make_loaded_module

  PATH="${fake_bin}:${PATH}" run kmd_swap

  [ "$status" -eq 0 ]
  [ "$(cat "$TT_KMD_LOADED_MARKER")" = "tenstorrent" ]
  mapfile -t calls <"$TT_KMD_LOG"
  [ "${calls[0]}" = "sudo rmmod tenstorrent" ]
  [ "${calls[1]}" = "rmmod tenstorrent" ]
  [ "${calls[2]}" = "sudo modprobe tenstorrent" ]
  [ "${calls[3]}" = "modprobe tenstorrent" ]
  [[ "$output" == *"tenstorrent KMD module is loaded"* ]]
}

@test "kmd_swap restores the previous module when modprobe fails" {
  fake_bin="$(make_fake_swap_tools)"
  make_loaded_module

  PATH="${fake_bin}:${PATH}" TT_KMD_FAIL_FIRST_MODPROBE=1 run kmd_swap

  [ "$status" -eq 1 ]
  [ "$(cat "$TT_KMD_LOADED_MARKER")" = "tenstorrent" ]
  [ "$(cat "$TT_KMD_MODPROBE_COUNT")" -eq 2 ]
  [[ "$output" == *"rolled back to previous module"* ]]
}

@test "kmd_swap loads the module without rmmod when it is not loaded" {
  fake_bin="$(make_fake_swap_tools)"

  PATH="${fake_bin}:${PATH}" run kmd_swap

  [ "$status" -eq 0 ]
  [ "$(cat "$TT_KMD_LOADED_MARKER")" = "tenstorrent" ]
  ! grep -q "rmmod" "$TT_KMD_LOG"
}

@test "kmd_swap stops before rmmod when preflight detects holders" {
  fake_bin="$(make_fake_swap_tools)"
  make_loaded_module
  mkdir -p "${BATS_TEST_TMPDIR}/dev/tenstorrent"
  touch "${BATS_TEST_TMPDIR}/dev/tenstorrent/0"
  cat >"${fake_bin}/lsof" <<'EOF'
#!/usr/bin/env bash
cat <<'OUT'
p1234
cpython
OUT
EOF
  chmod +x "${fake_bin}/lsof"

  PATH="${fake_bin}:${PATH}" run kmd_swap

  [ "$status" -eq 1 ]
  [ "$(cat "$TT_KMD_LOADED_MARKER")" = "tenstorrent" ]
  [[ "$output" == *"PID 1234 (python)"* ]]
  [[ "$output" == *"KMD preflight failed"* ]]
  [ ! -f "$TT_KMD_LOG" ] || ! grep -q "rmmod" "$TT_KMD_LOG"
}
