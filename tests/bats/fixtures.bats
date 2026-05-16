#!/usr/bin/env bats

setup() {
  REPO_DIR="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  MANIFEST_PARSER="${REPO_DIR}/lib/manifest_parser.sh"
}

@test "OS parser accepts repository ubuntu 22.04 manifest" {
  run bash -c '
    source "$1"
    parse_env_manifest "$2"
    printf "%s\n" "${TT_MANIFEST_SCALARS[PKG_MANAGER]}"
    printf "%s\n" "${TT_MANIFEST_SCALARS[VIRT_PKG_KMD]}"
    printf "%s\n" "${TT_MANIFEST_LIST_REQUIRED_REPOS[0]}"
  ' bash "$MANIFEST_PARSER" "${REPO_DIR}/manifests/ubuntu-22.04.env"

  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "apt" ]
  [ "${lines[1]}" = "tt-kmd-dkms" ]
  [ "${lines[2]}" = "ppa:tenstorrent/ppa" ]
}

@test "OS parser accepts repository ubuntu 24.04 manifest" {
  run bash -c '
    source "$1"
    parse_env_manifest "$2"
    printf "%s\n" "${TT_MANIFEST_SCALARS[PKG_MANAGER]}"
    printf "%s\n" "${TT_MANIFEST_SCALARS[VIRT_PKG_KMD]}"
    printf "%s\n" "${TT_MANIFEST_LIST_REQUIRED_REPOS[0]}"
  ' bash "$MANIFEST_PARSER" "${REPO_DIR}/manifests/ubuntu-24.04.env"

  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "apt" ]
  [ "${lines[1]}" = "tt-kmd-dkms" ]
  [ "${lines[2]}" = "ppa:tenstorrent/ppa" ]
}

@test "OS parser accepts repository Linux Mint 22.1 manifest" {
  run bash -c '
    source "$1"
    parse_env_manifest "$2"
    printf "%s\n" "${TT_MANIFEST_SCALARS[PKG_MANAGER]}"
    printf "%s\n" "${TT_MANIFEST_SCALARS[USE_SYSTEM_PACKAGES]}"
    printf "%s\n" "${TT_MANIFEST_SCALARS[VIRT_PKG_KMD]}"
    printf "%s\n" "${TT_MANIFEST_LIST_REQUIRED_REPOS[0]}"
  ' bash "$MANIFEST_PARSER" "${REPO_DIR}/manifests/linuxmint-22.1.env"

  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "apt" ]
  [ "${lines[1]}" = "true" ]
  [ "${lines[2]}" = "tt-kmd-dkms" ]
  [ "${lines[3]}" = "ppa:tenstorrent/ppa" ]
}

@test "OS parser accepts Fedora dnf fixture" {
  run bash -c '
    source "$1"
    parse_env_manifest "$2"
    printf "%s\n" "${TT_MANIFEST_SCALARS[PKG_MANAGER]}"
    printf "%s\n" "${TT_MANIFEST_SCALARS[VIRT_PKG_ZLIB]}"
    printf "%s\n" "${#TT_MANIFEST_LIST_REQUIRED_REPOS[@]}"
  ' bash "$MANIFEST_PARSER" "${REPO_DIR}/tests/fixtures/manifests/fedora-40.env"

  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "dnf" ]
  [ "${lines[1]}" = "zlib-devel" ]
  [ "${lines[2]}" = "0" ]
}

@test "parse_stack_manifest accepts repository proto-stack-2026.05.16 release" {
  run env TT_MANIFEST_DISABLE_JQ=1 bash -c '
    source "$1"
    parse_stack_manifest "$2"
    printf "%s\n" "$TT_STACK_RELEASE"
    printf "%s\n" "${TT_STACK_COMPONENTS[tt-metal]}"
  ' bash "$MANIFEST_PARSER" "${REPO_DIR}/releases/proto-stack-2026.05.16.json"

  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "proto-stack-2026.05.16" ]
  [ "${lines[1]}" = "v0.70.1" ]
}

@test "test fixtures mirror repository sample manifests" {
  run cmp -s "${REPO_DIR}/manifests/ubuntu-22.04.env" "${REPO_DIR}/tests/fixtures/manifests/ubuntu-22.04.env"
  [ "$status" -eq 0 ]

  run cmp -s "${REPO_DIR}/manifests/ubuntu-24.04.env" "${REPO_DIR}/tests/fixtures/manifests/ubuntu-24.04.env"
  [ "$status" -eq 0 ]

  run cmp -s "${REPO_DIR}/manifests/linuxmint-22.1.env" "${REPO_DIR}/tests/fixtures/manifests/linuxmint-22.1.env"
  [ "$status" -eq 0 ]

  run cmp -s "${REPO_DIR}/releases/proto-stack-2026.05.16.json" "${REPO_DIR}/tests/fixtures/releases/proto-stack-2026.05.16.json"
  [ "$status" -eq 0 ]
}
