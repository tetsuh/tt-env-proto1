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
# shellcheck disable=SC2034 # copied into via nameref and read via name arguments
declare -gA TT_RELEASE_DIFF_LEFT_COMPONENTS=()
# shellcheck disable=SC2034 # copied into via nameref and read via name arguments
declare -gA TT_RELEASE_DIFF_RIGHT_COMPONENTS=()
# shellcheck disable=SC2034 # copied into via nameref and read via name arguments
declare -gA TT_RELEASE_DIFF_LEFT_SYSTEM_PACKAGES=()
# shellcheck disable=SC2034 # copied into via nameref and read via name arguments
declare -gA TT_RELEASE_DIFF_RIGHT_SYSTEM_PACKAGES=()
# shellcheck disable=SC2034 # copied into via nameref and read via name arguments
declare -gA TT_RELEASE_DIFF_LEFT_PYTHON_PACKAGES=()
# shellcheck disable=SC2034 # copied into via nameref and read via name arguments
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
        left | right) ;;
        *)
            fail "Invalid diff side: ${side}"
            ;;
    esac

    local -n rel_target="TT_RELEASE_DIFF_${side^^}_RELEASE"
    local -n comp_target="TT_RELEASE_DIFF_${side^^}_COMPONENTS"
    local -n sys_target="TT_RELEASE_DIFF_${side^^}_SYSTEM_PACKAGES"
    local -n py_target="TT_RELEASE_DIFF_${side^^}_PYTHON_PACKAGES"

    rel_target="$TT_STACK_RELEASE"
    comp_target=()
    sys_target=()
    py_target=()

    for key in "${!TT_STACK_COMPONENTS[@]}"; do
        comp_target["$key"]="${TT_STACK_COMPONENTS[$key]}"
    done
    for key in "${!TT_STACK_SYSTEM_PACKAGES[@]}"; do
        sys_target["$key"]="${TT_STACK_SYSTEM_PACKAGES[$key]}"
    done
    for key in "${!TT_STACK_PYTHON_PACKAGES[@]}"; do
        py_target["$key"]="${TT_STACK_PYTHON_PACKAGES[$key]}"
    done
}

_diff_print_row() {
    printf '%-32s %-24s %-24s\n' "$1" "$2" "$3"
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
        _diff_print_row "$item" "$left_value" "$right_value"
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

    _diff_print_row "Item" "$TT_RELEASE_DIFF_LEFT_RELEASE" "$TT_RELEASE_DIFF_RIGHT_RELEASE"
    _diff_print_section "components" TT_RELEASE_DIFF_LEFT_COMPONENTS TT_RELEASE_DIFF_RIGHT_COMPONENTS
    _diff_print_section "system_packages" TT_RELEASE_DIFF_LEFT_SYSTEM_PACKAGES TT_RELEASE_DIFF_RIGHT_SYSTEM_PACKAGES
    _diff_print_section "python_packages" TT_RELEASE_DIFF_LEFT_PYTHON_PACKAGES TT_RELEASE_DIFF_RIGHT_PYTHON_PACKAGES
}
