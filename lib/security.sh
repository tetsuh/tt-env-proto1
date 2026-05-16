#!/usr/bin/env bash
# Security helpers for tt-env.
#
# Public symbols:
#   - calculate_sha256 <file>
#   - verify_sha256 <file> <expected-sha256>
#   - validate_workarounds [workaround-key...]
#   - workaround_handler_for <workaround-key>

if [[ -n "${TT_SECURITY_LOADED:-}" ]]; then
    return 0
fi
TT_SECURITY_LOADED=1

SECURITY_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SECURITY_LIB_DIR}/core.sh"

declare -gA TT_WORKAROUND_ALLOWLIST=(
    [ENABLE_IOMMU]="tt_security_workaround_enable_iommu"
)

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

tt_security_workaround_enable_iommu() {
    log_info "Workaround ENABLE_IOMMU is allowlisted."
}

workaround_handler_for() {
    local workaround_key="$1"
    local handler

    [[ -n "$workaround_key" ]] || fail "Unsupported WORKAROUNDS entry: <empty>"
    if [[ ! "$workaround_key" =~ ^[A-Z_][A-Z0-9_]*$ ]]; then
        fail "Unsupported WORKAROUNDS entry: ${workaround_key}"
    fi

    handler="${TT_WORKAROUND_ALLOWLIST[$workaround_key]:-}"
    [[ -n "$handler" ]] || fail "Unsupported WORKAROUNDS entry: ${workaround_key}"
    declare -F "$handler" >/dev/null || \
        fail "Allowlisted WORKAROUNDS entry ${workaround_key} maps to missing handler: ${handler}"

    printf '%s\n' "$handler"
}

validate_workarounds() {
    local workaround_key

    for workaround_key in "$@"; do
        workaround_handler_for "$workaround_key" >/dev/null
    done
}
