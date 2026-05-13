#!/usr/bin/env bats

setup() {
  CORE_SH="${BATS_TEST_DIRNAME}/../../lib/core.sh"
}

@test "detect_os reads ubuntu 22.04 from os-release" {
  os_release="${BATS_TEST_TMPDIR}/os-release"
  printf '%s\n' \
    'NAME="Ubuntu"' \
    'ID=ubuntu' \
    'VERSION_ID="22.04"' >"$os_release"

  run bash -c 'source "$1"; detect_os "$2"; printf "%s %s\n" "$OS_ID" "$OS_VERSION"' bash "$CORE_SH" "$os_release"
  [ "$status" -eq 0 ]
  [ "$output" = "ubuntu 22.04" ]
}

@test "detect_os reads ubuntu 24.04 from os-release" {
  os_release="${BATS_TEST_TMPDIR}/os-release"
  printf '%s\n' \
    'NAME="Ubuntu"' \
    'ID=ubuntu' \
    'VERSION_ID="24.04"' >"$os_release"

  run bash -c 'source "$1"; detect_os "$2"; printf "%s %s\n" "$OS_ID" "$OS_VERSION"' bash "$CORE_SH" "$os_release"
  [ "$status" -eq 0 ]
  [ "$output" = "ubuntu 24.04" ]
}

@test "detect_os reads Linux Mint 22.1 from os-release" {
  os_release="${BATS_TEST_TMPDIR}/os-release"
  printf '%s\n' \
    'NAME="Linux Mint"' \
    'ID=linuxmint' \
    'ID_LIKE="ubuntu debian"' \
    'VERSION_ID="22.1"' \
    'VERSION_CODENAME=xia' \
    'UBUNTU_CODENAME=noble' >"$os_release"

  run bash -c 'source "$1"; detect_os "$2"; printf "%s %s\n" "$OS_ID" "$OS_VERSION"' bash "$CORE_SH" "$os_release"
  [ "$status" -eq 0 ]
  [ "$output" = "linuxmint 22.1" ]
}

@test "detect_os honors TT_OVERRIDE_OS_ID and TT_OVERRIDE_OS_VERSION" {
  missing_os_release="${BATS_TEST_TMPDIR}/missing-os-release"

  run env TT_OVERRIDE_OS_ID=ubuntu TT_OVERRIDE_OS_VERSION=22.04 \
    bash -c 'source "$1"; detect_os "$2"; printf "%s %s\n" "$OS_ID" "$OS_VERSION"' \
    bash "$CORE_SH" "$missing_os_release"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ubuntu 22.04"* ]]
}

@test "detect_os honors Ubuntu 24.04 override" {
  missing_os_release="${BATS_TEST_TMPDIR}/missing-os-release"

  run env TT_OVERRIDE_OS_ID=ubuntu TT_OVERRIDE_OS_VERSION=24.04 \
    bash -c 'source "$1"; detect_os "$2"; printf "%s %s\n" "$OS_ID" "$OS_VERSION"' \
    bash "$CORE_SH" "$missing_os_release"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ubuntu 24.04"* ]]
}

@test "detect_os honors Linux Mint 22.1 override" {
  missing_os_release="${BATS_TEST_TMPDIR}/missing-os-release"

  run env TT_OVERRIDE_OS_ID=linuxmint TT_OVERRIDE_OS_VERSION=22.1 \
    bash -c 'source "$1"; detect_os "$2"; printf "%s %s\n" "$OS_ID" "$OS_VERSION"' \
    bash "$CORE_SH" "$missing_os_release"
  [ "$status" -eq 0 ]
  [[ "$output" == *"linuxmint 22.1"* ]]
}

@test "detect_os fails when os-release is missing" {
  missing_os_release="${BATS_TEST_TMPDIR}/missing-os-release"

  run bash -c 'source "$1"; detect_os "$2"' bash "$CORE_SH" "$missing_os_release"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Cannot detect OS"* ]]
}
