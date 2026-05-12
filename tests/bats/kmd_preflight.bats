#!/usr/bin/env bats

setup() {
  REPO_DIR="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export TT_HOME="${BATS_TEST_TMPDIR}/tt-home"
  export TT_KMD_DEVICE_GLOB="${BATS_TEST_TMPDIR}/dev/tenstorrent/*"
  source "${REPO_DIR}/lib/kmd.sh"
}

make_device_nodes() {
  mkdir -p "${BATS_TEST_TMPDIR}/dev/tenstorrent"
  touch "${BATS_TEST_TMPDIR}/dev/tenstorrent/0"
  touch "${BATS_TEST_TMPDIR}/dev/tenstorrent/1"
}

make_fake_lsof() {
  local fake_bin="${BATS_TEST_TMPDIR}/fake-lsof-bin"

  mkdir -p "$fake_bin"
  cat >"${fake_bin}/lsof" <<'EOF'
#!/bin/sh
cat <<'OUT'
p1234
cpython
p5678
ctt-smi
OUT
EOF
  chmod +x "${fake_bin}/lsof"
  printf '%s\n' "$fake_bin"
}

make_fake_fuser_and_ps() {
  local fake_bin="${BATS_TEST_TMPDIR}/fake-fuser-bin"

  mkdir -p "$fake_bin"
  cat >"${fake_bin}/fuser" <<'EOF'
#!/bin/sh
printf '2468 1357\n'
EOF
  cat >"${fake_bin}/ps" <<'EOF'
#!/bin/sh
case "$2" in
  2468) printf 'python\n' ;;
  1357) printf 'tt-smi\n' ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "${fake_bin}/fuser" "${fake_bin}/ps"
  printf '%s\n' "$fake_bin"
}

@test "kmd_preflight passes when no device nodes exist" {
  run kmd_preflight

  [ "$status" -eq 0 ]
  [[ "$output" == *"No Tenstorrent device nodes found"* ]]
}

@test "kmd_preflight reports lsof holders by PID and command" {
  make_device_nodes
  fake_bin="$(make_fake_lsof)"

  PATH="${fake_bin}:${PATH}" run kmd_preflight

  [ "$status" -eq 1 ]
  [[ "$output" == *"Tenstorrent devices are in use"* ]]
  [[ "$output" == *"PID 1234 (python)"* ]]
  [[ "$output" == *"PID 5678 (tt-smi)"* ]]
}

@test "kmd_preflight falls back to fuser when lsof is unavailable" {
  make_device_nodes
  fake_bin="$(make_fake_fuser_and_ps)"

  PATH="$fake_bin" run kmd_preflight

  [ "$status" -eq 1 ]
  [[ "$output" == *"PID 2468 (python)"* ]]
  [[ "$output" == *"PID 1357 (tt-smi)"* ]]
}

@test "kmd_preflight fails closed when no preflight tool exists" {
  make_device_nodes
  fake_bin="${BATS_TEST_TMPDIR}/empty-bin"
  mkdir -p "$fake_bin"

  PATH="$fake_bin" run kmd_preflight

  [ "$status" -eq 1 ]
  [[ "$output" == *"KMD preflight requires lsof or fuser"* ]]
}
