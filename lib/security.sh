#!/usr/bin/env bash
# Security helpers for tt-env.
#
# Public symbols:
#   - calculate_sha256 <file>
#   - verify_sha256 <file> <expected-sha256>

if [[ -n "${TT_SECURITY_LOADED:-}" ]]; then
    return 0
fi
TT_SECURITY_LOADED=1

SECURITY_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SECURITY_LIB_DIR}/core.sh"

calculate_sha256() {
    local file="$1"
    local output

    [[ -f "$file" ]] || fail "Cannot calculate sha256; file not found: ${file}"

    if command_exists sha256sum; then
        output="$(sha256sum "$file")"
        printf '%s\n' "${output%% *}"
    elif command_exists shasum; then
        output="$(shasum -a 256 "$file")"
        printf '%s\n' "${output%% *}"
    else
        fail "sha256sum or shasum is required to verify downloaded artifacts."
    fi
}

verify_sha256() {
    local file="$1"
    local expected_sha256="${2,,}"
    local actual_sha256

    actual_sha256="$(calculate_sha256 "$file")"
    actual_sha256="${actual_sha256,,}"

    if [[ "$actual_sha256" != "$expected_sha256" ]]; then
        fail "sha256 mismatch for ${file}: expected ${expected_sha256}, got ${actual_sha256}"
    fi
}
