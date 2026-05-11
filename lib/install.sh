#!/usr/bin/env bash
# Install command helpers for tt-env.
#
# Public symbols:
#   - install_release [--dry-run] [--force] <release>

if [[ -n "${TT_INSTALL_LOADED:-}" ]]; then
    return 0
fi
TT_INSTALL_LOADED=1

INSTALL_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_ROOT="$(cd "${INSTALL_LIB_DIR}/.." && pwd)"
# shellcheck disable=SC1091
source "${INSTALL_LIB_DIR}/core.sh"
# shellcheck disable=SC1091
source "${INSTALL_LIB_DIR}/manifest_parser.sh"

_install_usage() {
    cat <<'EOF'
Usage:
  tt-env install [--dry-run] [--force] <release>
EOF
}

_install_validate_release_name() {
    local release="$1"

    if [[ ! "$release" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]; then
        fail "Invalid release name: ${release}"
    fi

    case "$release" in
        .|..|*/*|*\\*)
            fail "Invalid release name: ${release}"
            ;;
    esac
}

_install_stack_manifest_path() {
    local release="$1"
    local tt_home_manifest="${TT_HOME}/releases/${release}.json"
    local bundled_manifest="${INSTALL_ROOT}/releases/${release}.json"

    if [[ -f "$tt_home_manifest" ]]; then
        printf '%s\n' "$tt_home_manifest"
    elif [[ -f "$bundled_manifest" ]]; then
        printf '%s\n' "$bundled_manifest"
    else
        fail "Release manifest not found for ${release}."
    fi
}

_install_remove_version_dir() {
    local versions_dir="$1"
    local version_dir="$2"
    local physical_versions_dir
    local physical_parent_dir

    physical_versions_dir="$(cd "$versions_dir" && pwd -P)"
    physical_parent_dir="$(cd "$(dirname "$version_dir")" && pwd -P)"

    if [[ "$physical_parent_dir" != "$physical_versions_dir" || "$version_dir" == "$versions_dir" ]]; then
        fail "Refusing to remove unsafe version directory: ${version_dir}"
    fi

    log_info "Removing existing version directory: ${version_dir}"
    rm -rf -- "$version_dir"
}

install_release() {
    local dry_run=0
    local force=0
    local release=""
    local arg

    while [[ "$#" -gt 0 ]]; do
        arg="$1"
        case "$arg" in
            --dry-run)
                dry_run=1
                ;;
            --force)
                force=1
                ;;
            --help|-h)
                _install_usage
                return 0
                ;;
            --*)
                fail "Unknown install option: ${arg}"
                ;;
            *)
                if [[ -n "$release" ]]; then
                    fail "install accepts exactly one release."
                fi
                release="$arg"
                ;;
        esac
        shift
    done

    if [[ -z "$release" ]]; then
        _install_usage >&2
        return 1
    fi

    _install_validate_release_name "$release"
    init_tt_home

    local manifest_file
    local versions_dir="${TT_HOME}/versions"
    local version_dir="${versions_dir}/${release}"
    local installed_marker="${version_dir}/.tt-env-installed"

    manifest_file="$(_install_stack_manifest_path "$release")"
    parse_stack_manifest "$manifest_file"

    if [[ "$TT_STACK_RELEASE" != "$release" ]]; then
        fail "Release manifest ${manifest_file} declares ${TT_STACK_RELEASE}, expected ${release}."
    fi

    if [[ -f "$installed_marker" && "$force" -eq 0 ]]; then
        log_info "Release ${release} is already installed at ${version_dir}."
        return 0
    fi

    if [[ -e "$version_dir" && ! -f "$installed_marker" && "$force" -eq 0 ]]; then
        fail "Version directory exists but is not marked installed: ${version_dir}. Use --force to recreate it."
    fi

    if [[ "$dry_run" -eq 1 ]]; then
        if [[ -e "$version_dir" && "$force" -eq 1 ]]; then
            log_info "[dry-run] Would remove existing version directory: ${version_dir}"
        fi
        log_info "[dry-run] Would create version directory: ${version_dir}"
        return 0
    fi

    mkdir -p "$versions_dir" || fail "Failed to create versions directory: ${versions_dir}"

    if [[ -e "$version_dir" && "$force" -eq 1 ]]; then
        _install_remove_version_dir "$versions_dir" "$version_dir"
    fi

    mkdir -p "$version_dir" || fail "Failed to create version directory: ${version_dir}"
    printf 'release=%s\n' "$release" >"$installed_marker" || \
        fail "Failed to write installed marker: ${installed_marker}"

    log_info "Installed release ${release} at ${version_dir}."
}
