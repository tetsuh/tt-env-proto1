#!/usr/bin/env bash
# Release manifest comparison helpers for tt-env.
#
# Public symbols:
#   - diff_releases <release-a> <release-b>

if [[ -n "${TT_RELEASE_DIFF_LOADED:-}" ]]; then
    return 0
fi
TT_RELEASE_DIFF_LOADED=1

RELEASE_DIFF_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASE_DIFF_ROOT="$(cd "${RELEASE_DIFF_LIB_DIR}/.." && pwd)"
# shellcheck disable=SC1091
source "${RELEASE_DIFF_LIB_DIR}/core.sh"
# shellcheck disable=SC1091
source "${RELEASE_DIFF_LIB_DIR}/manifest_parser.sh"

declare -g TT_RELEASE_DIFF_LEFT_RELEASE=""
declare -g TT_RELEASE_DIFF_RIGHT_RELEASE=""
declare -gA TT_RELEASE_DIFF_LEFT_COMPONENTS=()
declare -gA TT_RELEASE_DIFF_RIGHT_COMPONENTS=()
declare -gA TT_RELEASE_DIFF_LEFT_SYSTEM_PACKAGES=()
declare -gA TT_RELEASE_DIFF_RIGHT_SYSTEM_PACKAGES=()
declare -gA TT_RELEASE_DIFF_LEFT_PYTHON_PACKAGES=()
declare -gA TT_RELEASE_DIFF_RIGHT_PYTHON_PACKAGES=()

_diff_usage() {
    cat <<'EOF'
tt-env diff - compare two stack release manifests

Usage:
  tt-env diff <release-a> <release-b>
EOF
}

_diff_validate_release_name() {
    local release="$1"

    [[ "$release" =~ ^[A-Za-z0-9._-]+$ ]] || fail "Invalid release name: ${release}"
}

_diff_stack_manifest_path() {
    local release="$1"
    local tt_home_manifest="${TT_HOME}/releases/${release}.json"
    local bundled_manifest="${RELEASE_DIFF_ROOT}/releases/${release}.json"

    _diff_validate_release_name "$release"

    if [[ -f "$tt_home_manifest" ]]; then
        printf '%s\n' "$tt_home_manifest"
    elif [[ -f "$bundled_manifest" ]]; then
        printf '%s\n' "$bundled_manifest"
    else
        fail "Release manifest not found for ${release}."
    fi
}

_diff_copy_current_stack() {
    local side="$1"
    local key

    case "$side" in
        left)
            TT_RELEASE_DIFF_LEFT_RELEASE="$TT_STACK_RELEASE"
            TT_RELEASE_DIFF_LEFT_COMPONENTS=()
            TT_RELEASE_DIFF_LEFT_SYSTEM_PACKAGES=()
            TT_RELEASE_DIFF_LEFT_PYTHON_PACKAGES=()
            for key in "${!TT_STACK_COMPONENTS[@]}"; do
                TT_RELEASE_DIFF_LEFT_COMPONENTS["$key"]="${TT_STACK_COMPONENTS[$key]}"
            done
            for key in "${!TT_STACK_SYSTEM_PACKAGES[@]}"; do
                TT_RELEASE_DIFF_LEFT_SYSTEM_PACKAGES["$key"]="${TT_STACK_SYSTEM_PACKAGES[$key]}"
            done
            for key in "${!TT_STACK_PYTHON_PACKAGES[@]}"; do
                TT_RELEASE_DIFF_LEFT_PYTHON_PACKAGES["$key"]="${TT_STACK_PYTHON_PACKAGES[$key]}"
            done
            ;;
        right)
            TT_RELEASE_DIFF_RIGHT_RELEASE="$TT_STACK_RELEASE"
            TT_RELEASE_DIFF_RIGHT_COMPONENTS=()
            TT_RELEASE_DIFF_RIGHT_SYSTEM_PACKAGES=()
            TT_RELEASE_DIFF_RIGHT_PYTHON_PACKAGES=()
            for key in "${!TT_STACK_COMPONENTS[@]}"; do
                TT_RELEASE_DIFF_RIGHT_COMPONENTS["$key"]="${TT_STACK_COMPONENTS[$key]}"
            done
            for key in "${!TT_STACK_SYSTEM_PACKAGES[@]}"; do
                TT_RELEASE_DIFF_RIGHT_SYSTEM_PACKAGES["$key"]="${TT_STACK_SYSTEM_PACKAGES[$key]}"
            done
            for key in "${!TT_STACK_PYTHON_PACKAGES[@]}"; do
                TT_RELEASE_DIFF_RIGHT_PYTHON_PACKAGES["$key"]="${TT_STACK_PYTHON_PACKAGES[$key]}"
            done
            ;;
        *)
            fail "Invalid diff side: ${side}"
            ;;
    esac
}

_diff_load_release() {
    local release="$1"
    local side="$2"
    local manifest_file

    manifest_file="$(_diff_stack_manifest_path "$release")"
    parse_stack_manifest "$manifest_file"
    _diff_copy_current_stack "$side"
}

_diff_print_section() {
    local prefix="$1"
    local left_array="$2"
    local right_array="$3"
    local -n left_ref="$left_array"
    local -n right_ref="$right_array"
    local key
    local item
    local left_value
    local right_value
    local -a keys=()

    mapfile -t keys < <(
        {
            printf '%s\n' "${!left_ref[@]}"
            printf '%s\n' "${!right_ref[@]}"
        } | sed '/^$/d' | sort -u
    )

    for key in "${keys[@]}"; do
        item="${prefix}.${key}"
        left_value="${left_ref[$key]:--}"
        right_value="${right_ref[$key]:--}"
        printf '%-32s %-18s %-18s\n' "$item" "$left_value" "$right_value"
    done
}

diff_releases() {
    local left_release="${1:-}"
    local right_release="${2:-}"

    if [[ "$#" -ne 2 || "$left_release" == "--help" || "$left_release" == "-h" ]]; then
        _diff_usage
        return 1
    fi

    _diff_load_release "$left_release" left
    _diff_load_release "$right_release" right

    printf '%-32s %-18s %-18s\n' "Item" "$TT_RELEASE_DIFF_LEFT_RELEASE" "$TT_RELEASE_DIFF_RIGHT_RELEASE"
    _diff_print_section "components" TT_RELEASE_DIFF_LEFT_COMPONENTS TT_RELEASE_DIFF_RIGHT_COMPONENTS
    _diff_print_section "system_packages" TT_RELEASE_DIFF_LEFT_SYSTEM_PACKAGES TT_RELEASE_DIFF_RIGHT_SYSTEM_PACKAGES
    _diff_print_section "python_packages" TT_RELEASE_DIFF_LEFT_PYTHON_PACKAGES TT_RELEASE_DIFF_RIGHT_PYTHON_PACKAGES
}
