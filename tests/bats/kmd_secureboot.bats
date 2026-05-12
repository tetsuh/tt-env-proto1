#!/usr/bin/env bats

setup() {
  REPO_DIR="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export TT_HOME="${BATS_TEST_TMPDIR}/tt-home"
  export TT_KMD_LOG="${BATS_TEST_TMPDIR}/kmd-secureboot.log"
  export TT_KMD_LOADED_MARKER="${BATS_TEST_TMPDIR}/tenstorrent.loaded"
  export TT_MODPROBE_MARKER="${BATS_TEST_TMPDIR}/modprobe.loaded"
  export TT_KMD_DEVICE_GLOB="${BATS_TEST_TMPDIR}/dev/tenstorrent/*"
  export TT_KMD_EFI_DIR="${BATS_TEST_TMPDIR}/sys/firmware/efi"
  source "${REPO_DIR}/lib/kmd.sh"
}

make_fake_secureboot_tools() {
  local secure_boot_state="$1"
  local fake_bin="${BATS_TEST_TMPDIR}/fake-secureboot-bin"

  mkdir -p "$fake_bin" "$TT_KMD_EFI_DIR"
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
  cat >"${fake_bin}/mokutil" <<EOF
#!/usr/bin/env bash
printf 'mokutil %s\\n' "\$*" >>"\$TT_KMD_LOG"
printf '${secure_boot_state}\\n'
EOF
  chmod +x "${fake_bin}/sudo" "${fake_bin}/apt-get" "${fake_bin}/modprobe" \
    "${fake_bin}/lsmod" "${fake_bin}/rmmod" "${fake_bin}/mokutil"
  printf '%s\n' "$fake_bin"
}

@test "kmd_install aborts when Secure Boot is enabled" {
  fake_bin="$(make_fake_secureboot_tools "SecureBoot enabled")"

  PATH="${fake_bin}:${PATH}" run kmd_install

  [ "$status" -eq 1 ]
  [[ "$output" == *"tt-env proto1 does not support Secure Boot"* ]]
  grep -q "mokutil --sb-state" "$TT_KMD_LOG"
  ! grep -q "apt-get install" "$TT_KMD_LOG"
  [ ! -f "$TT_MODPROBE_MARKER" ]
}

@test "kmd_install proceeds when Secure Boot is disabled" {
  fake_bin="$(make_fake_secureboot_tools "SecureBoot disabled")"

  PATH="${fake_bin}:${PATH}" run kmd_install

  [ "$status" -eq 0 ]
  grep -q "mokutil --sb-state" "$TT_KMD_LOG"
  grep -q "apt-get install -y tt-kmd-dkms" "$TT_KMD_LOG"
  [ "$(cat "$TT_MODPROBE_MARKER")" = "tenstorrent" ]
}

@test "kmd_swap aborts before rmmod when Secure Boot is enabled" {
  fake_bin="$(make_fake_secureboot_tools "SecureBoot enabled")"
  printf 'tenstorrent\n' >"$TT_KMD_LOADED_MARKER"

  PATH="${fake_bin}:${PATH}" run kmd_swap

  [ "$status" -eq 1 ]
  [[ "$output" == *"tt-env proto1 does not support Secure Boot"* ]]
  [ "$(cat "$TT_KMD_LOADED_MARKER")" = "tenstorrent" ]
  ! grep -q "rmmod" "$TT_KMD_LOG"
}

@test "kmd operations fail closed when mokutil is unavailable" {
  fake_bin="$(make_fake_secureboot_tools "SecureBoot disabled")"
  rm -f "${fake_bin}/mokutil"

  PATH="$fake_bin" run kmd_install

  [ "$status" -eq 1 ]
  [[ "$output" == *"mokutil is required to verify Secure Boot state on EFI systems"* ]]
  [ ! -f "$TT_MODPROBE_MARKER" ]
}

@test "kmd operations skip mokutil when EFI is unavailable" {
  fake_bin="$(make_fake_secureboot_tools "SecureBoot enabled")"
  rm -rf "$TT_KMD_EFI_DIR"
  rm -f "${fake_bin}/mokutil"

  PATH="${fake_bin}:${PATH}" run kmd_install

  [ "$status" -eq 0 ]
  ! grep -q "mokutil --sb-state" "$TT_KMD_LOG"
  grep -q "apt-get install -y tt-kmd-dkms" "$TT_KMD_LOG"
  [ "$(cat "$TT_MODPROBE_MARKER")" = "tenstorrent" ]
}
