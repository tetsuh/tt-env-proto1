#!/usr/bin/env bats

setup() {
  MANIFEST_PARSER="${BATS_TEST_DIRNAME}/../../lib/manifest_parser.sh"
}

write_valid_manifest() {
  local manifest_file="$1"
  cat >"$manifest_file" <<'EOF'
# Manifest for Ubuntu 22.04

# Native Package Manager
PKG_MANAGER="apt"
USE_PPA="true"

# Required Repositories (e.g., PPA)
REQUIRED_REPOS=(
    "ppa:tenstorrent/ppa"
)

# Virtual Package Mappings
VIRT_PKG_CMAKE="cmake"
VIRT_PKG_NINJA="ninja-build"
VIRT_PKG_ZLIB="zlib1g-dev"
VIRT_PKG_KMD="tenstorrent-dkms"

# OS Specific Workarounds
WORKAROUNDS=()
EOF
}

@test "parse_env_manifest parses ubuntu 22.04 manifest shape" {
  manifest_file="${BATS_TEST_TMPDIR}/ubuntu-22.04.env"
  write_valid_manifest "$manifest_file"

  run bash -c '
    source "$1"
    parse_env_manifest "$2"
    printf "%s\n" "${TT_MANIFEST_SCALARS[PKG_MANAGER]}"
    printf "%s\n" "${TT_MANIFEST_SCALARS[USE_PPA]}"
    printf "%s\n" "${TT_MANIFEST_SCALARS[VIRT_PKG_KMD]}"
    printf "%s\n" "${TT_MANIFEST_LIST_REQUIRED_REPOS[0]}"
    printf "%s\n" "${#TT_MANIFEST_LIST_WORKAROUNDS[@]}"
  ' bash "$MANIFEST_PARSER" "$manifest_file"

  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "apt" ]
  [ "${lines[1]}" = "true" ]
  [ "${lines[2]}" = "tenstorrent-dkms" ]
  [ "${lines[3]}" = "ppa:tenstorrent/ppa" ]
  [ "${lines[4]}" = "0" ]
}

@test "parse_env_manifest rejects command substitution" {
  manifest_file="${BATS_TEST_TMPDIR}/attack.env"
  printf '%s\n' 'PKG_MANAGER="$(uname)"' >"$manifest_file"

  run bash -c 'source "$1"; parse_env_manifest "$2"' bash "$MANIFEST_PARSER" "$manifest_file"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Rejected unsafe manifest line"* ]]
}

@test "parse_env_manifest rejects backticks" {
  manifest_file="${BATS_TEST_TMPDIR}/attack.env"
  printf '%s\n' 'PKG_MANAGER="`uname`"' >"$manifest_file"

  run bash -c 'source "$1"; parse_env_manifest "$2"' bash "$MANIFEST_PARSER" "$manifest_file"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Rejected unsafe manifest line"* ]]
}

@test "parse_env_manifest rejects semicolon commands" {
  manifest_file="${BATS_TEST_TMPDIR}/attack.env"
  printf '%s\n' 'PKG_MANAGER="apt";rm -rf /' >"$manifest_file"

  run bash -c 'source "$1"; parse_env_manifest "$2"' bash "$MANIFEST_PARSER" "$manifest_file"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Rejected unsafe manifest line"* ]]
}

@test "parse_env_manifest rejects curl command substitution without executing it" {
  manifest_file="${BATS_TEST_TMPDIR}/attack.env"
  marker="${BATS_TEST_TMPDIR}/executed"
  printf 'PKG_MANAGER="$(curl file://%s)"\n' "$marker" >"$manifest_file"

  run bash -c 'source "$1"; parse_env_manifest "$2"' bash "$MANIFEST_PARSER" "$manifest_file"
  [ "$status" -ne 0 ]
  [ ! -e "$marker" ]
  [[ "$output" == *"Rejected unsafe manifest line"* ]]
}

@test "parse_env_manifest clears list globals between parses" {
  first="${BATS_TEST_TMPDIR}/first.env"
  second="${BATS_TEST_TMPDIR}/second.env"
  printf '%s\n' 'REQUIRED_REPOS=("ppa:first/ppa")' >"$first"
  printf '%s\n' 'PKG_MANAGER="apt"' >"$second"

  run bash -c '
    source "$1"
    parse_env_manifest "$2"
    parse_env_manifest "$3"
    declare -p TT_MANIFEST_LIST_REQUIRED_REPOS >/dev/null 2>&1
  ' bash "$MANIFEST_PARSER" "$first" "$second"

  [ "$status" -ne 0 ]
}

@test "parse_env_manifest allows empty quoted list items" {
  manifest_file="${BATS_TEST_TMPDIR}/empty-list-item.env"
  printf '%s\n' 'REQUIRED_REPOS=("" ppa:tenstorrent/ppa)' >"$manifest_file"

  run bash -c '
    source "$1"
    parse_env_manifest "$2"
    printf "<%s>\n" "${TT_MANIFEST_LIST_REQUIRED_REPOS[0]}"
    printf "%s\n" "${TT_MANIFEST_LIST_REQUIRED_REPOS[1]}"
  ' bash "$MANIFEST_PARSER" "$manifest_file"

  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "<>" ]
  [ "${lines[1]}" = "ppa:tenstorrent/ppa" ]
}
