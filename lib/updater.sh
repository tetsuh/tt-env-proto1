#!/usr/bin/env bash
# Manifest listing and update helpers for tt-env.
#
# Public symbols:
#   - list_releases

if [[ -n "${TT_UPDATER_LOADED:-}" ]]; then
    return 0
fi
TT_UPDATER_LOADED=1

UPDATER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${UPDATER_LIB_DIR}/core.sh"
# shellcheck disable=SC1091
source "${UPDATER_LIB_DIR}/manifest_parser.sh"

_list_usage() {
    cat <<'EOF'
Usage:
  tt-env list
EOF
}

_list_release_installed() {
    local release="$1"
    local version_dir="${TT_HOME}/versions/${release}"

    [[ -d "$version_dir" && -f "${version_dir}/.tt-env-installed" ]]
}

list_releases() {
    local arg
    local manifest_file
    local release
    local state
    local -a manifests=()

    while [[ "$#" -gt 0 ]]; do
        arg="$1"
        case "$arg" in
            --help|-h)
                _list_usage
                return 0
                ;;
            *)
                fail "Unknown list option: ${arg}"
                ;;
        esac
        shift
    done

    shopt -s nullglob
    manifests=("${TT_HOME}/releases/"*.json)
    shopt -u nullglob

    printf 'Releases\n'
    if [[ "${#manifests[@]}" -eq 0 ]]; then
        printf '  (none)\n'
        return 0
    fi

    for manifest_file in "${manifests[@]}"; do
        parse_stack_manifest "$manifest_file"
        release="$TT_STACK_RELEASE"

        if _list_release_installed "$release"; then
            state="installed"
        else
            state="available"
        fi

        printf '  %s [%s]\n' "$release" "$state"
    done
}

