#!/usr/bin/env bash
# Active version selection helpers for tt-env.
#
# Public symbols:
#   - use_release <release>

if [[ -n "${TT_VERSION_MANAGER_LOADED:-}" ]]; then
    return 0
fi
TT_VERSION_MANAGER_LOADED=1

VERSION_MANAGER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${VERSION_MANAGER_LIB_DIR}/core.sh"

_use_usage() {
    cat <<'EOF'
Usage:
  tt-env use <release>
EOF
}

_version_validate_release_name() {
    local release="$1"

    if [[ ! "$release" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]; then
        fail "Invalid release name: ${release}"
    fi
}

use_release() {
    local release=""
    local arg
    local version_dir
    local installed_marker
    local current_link
    local current_target

    while [[ "$#" -gt 0 ]]; do
        arg="$1"
        case "$arg" in
            --help|-h)
                _use_usage
                return 0
                ;;
            --*)
                fail "Unknown use option: ${arg}"
                ;;
            *)
                if [[ -n "$release" ]]; then
                    fail "use accepts exactly one release."
                fi
                release="$arg"
                ;;
        esac
        shift
    done

    if [[ -z "$release" ]]; then
        _use_usage >&2
        return 1
    fi

    _version_validate_release_name "$release"
    init_tt_home

    version_dir="${TT_HOME}/versions/${release}"
    installed_marker="${version_dir}/.tt-env-installed"
    current_link="${TT_HOME}/current"

    if [[ ! -d "$version_dir" || ! -f "$installed_marker" ]]; then
        fail "Release ${release} is not installed. Run: tt-env install ${release}"
    fi

    if [[ -e "$current_link" && ! -L "$current_link" ]]; then
        fail "Refusing to replace non-symlink current path: ${current_link}"
    fi

    ln -sfn "$version_dir" "$current_link" || \
        fail "Failed to switch current release to ${release}"

    if [[ ! -L "$current_link" ]]; then
        rm -rf -- "$current_link"
        fail "ln -sfn did not create a symlink: ${current_link}"
    fi

    current_target="$(readlink "$current_link")" || \
        fail "Failed to read current symlink: ${current_link}"

    if [[ "$current_target" != "$version_dir" ]]; then
        rm -f -- "$current_link"
        fail "ln -sfn did not create the expected symlink: ${current_link}"
    fi

    log_info "Using release ${release} at ${version_dir}."
}
