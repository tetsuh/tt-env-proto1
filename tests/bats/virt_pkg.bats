#!/usr/bin/env bats

setup() {
  MANIFEST_PARSER="${BATS_TEST_DIRNAME}/../../lib/manifest_parser.sh"
  MANIFEST_FILE="${BATS_TEST_TMPDIR}/packages.env"
  cat >"$MANIFEST_FILE" <<'EOF'
PKG_MANAGER="apt"
VIRT_PKG_CMAKE="cmake"
VIRT_PKG_NINJA="ninja-build"
VIRT_PKG_ZLIB="zlib1g-dev"
VIRT_PKG_KMD="tt-kmd-dkms"
EOF
}

@test "resolve_package returns native package for virtual package" {
  run bash -c '
    source "$1"
    parse_env_manifest "$2"
    resolve_package kmd
  ' bash "$MANIFEST_PARSER" "$MANIFEST_FILE"

  [ "$status" -eq 0 ]
  [ "$output" = "tt-kmd-dkms" ]
}

@test "resolve_package uppercases package names" {
  run bash -c '
    source "$1"
    parse_env_manifest "$2"
    resolve_package zlib
  ' bash "$MANIFEST_PARSER" "$MANIFEST_FILE"

  [ "$status" -eq 0 ]
  [ "$output" = "zlib1g-dev" ]
}

@test "resolve_package normalizes separators to underscores" {
  run bash -c '
    source "$1"
    TT_MANIFEST_SCALARS["VIRT_PKG_MY_PKG"]="dash-value"
    TT_MANIFEST_SCALARS["VIRT_PKG_LIBSSL_SO"]="dot-value"
    TT_MANIFEST_SCALARS["VIRT_PKG_STDC__"]="plus-value"
    resolve_package my-pkg
    resolve_package libssl.so
    resolve_package stdc++
  ' bash "$MANIFEST_PARSER"

  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "dash-value" ]
  [ "${lines[1]}" = "dot-value" ]
  [ "${lines[2]}" = "plus-value" ]
}

@test "resolve_package fails clearly for undefined package" {
  run bash -c '
    source "$1"
    parse_env_manifest "$2"
    resolve_package openssl
  ' bash "$MANIFEST_PARSER" "$MANIFEST_FILE"

  [ "$status" -eq 1 ]
  [[ "$output" == *"Virtual package is not defined: openssl (VIRT_PKG_OPENSSL)"* ]]
}
