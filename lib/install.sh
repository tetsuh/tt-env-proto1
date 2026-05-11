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

declare -ga TT_INSTALL_VIRTUAL_PACKAGES=("cmake" "ninja" "zlib" "kmd")

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

_install_os_manifest_path() {
    local os_id="$1"
    local os_version="$2"
    local manifest_name="${os_id}-${os_version}.env"
    local tt_home_manifest="${TT_HOME}/manifests/${manifest_name}"
    local bundled_manifest="${INSTALL_ROOT}/manifests/${manifest_name}"

    if [[ -f "$tt_home_manifest" ]]; then
        printf '%s\n' "$tt_home_manifest"
    elif [[ -f "$bundled_manifest" ]]; then
        printf '%s\n' "$bundled_manifest"
    else
        fail "OS manifest not found for ${os_id} ${os_version}."
    fi
}

_install_require_sudo() {
    if ! command_exists sudo; then
        fail "sudo is required to install apt packages. Install sudo or run on a system where sudo is available."
    fi
}

_install_require_apt_tools() {
    local repo_count="$1"

    if ! command_exists apt-get; then
        fail "apt-get is required to install apt packages."
    fi

    if [[ "$repo_count" -gt 0 ]] && ! command_exists add-apt-repository; then
        fail "add-apt-repository is required to add repositories. Install software-properties-common."
    fi
}

_install_required_repos() {
    if declare -p TT_MANIFEST_LIST_REQUIRED_REPOS >/dev/null 2>&1; then
        local -n manifest_repos=TT_MANIFEST_LIST_REQUIRED_REPOS
        if [[ "${#manifest_repos[@]}" -gt 0 ]]; then
            printf '%s\n' "${manifest_repos[@]}"
        fi
    fi
}

_install_resolved_packages() {
    local virtual_package

    for virtual_package in "${TT_INSTALL_VIRTUAL_PACKAGES[@]}"; do
        resolve_package "$virtual_package"
    done
}

_install_apt_packages() {
    local dry_run="$1"
    local -a repos=()
    local -a packages=()
    local repo

    mapfile -t repos < <(_install_required_repos)
    mapfile -t packages < <(_install_resolved_packages)

    if [[ "${#packages[@]}" -eq 0 ]]; then
        fail "No apt packages resolved from OS manifest."
    fi

    if [[ "$dry_run" -eq 1 ]]; then
        for repo in "${repos[@]}"; do
            log_info "[dry-run] Would add apt repository: ${repo}"
        done
        log_info "[dry-run] Would run apt-get update."
        log_info "[dry-run] Would install apt packages: ${packages[*]}"
        return 0
    fi

    _install_require_sudo
    _install_require_apt_tools "${#repos[@]}"

    for repo in "${repos[@]}"; do
        log_info "Adding apt repository: ${repo}"
        sudo add-apt-repository -y "$repo" || fail "Failed to add repository: ${repo}"
    done

    log_info "Updating apt package metadata."
    sudo apt-get update || fail "Failed to update apt package metadata."

    log_info "Installing apt packages: ${packages[*]}"
    sudo apt-get install -y "${packages[@]}" || fail "Failed to install apt packages."
}

_install_system_packages() {
    local dry_run="$1"
    local os_manifest
    local detected_os_id
    local detected_os_version
    local pkg_manager
    local use_ppa

    detect_os
    detected_os_id="${OS_ID:-}"
    detected_os_version="${OS_VERSION:-}"
    os_manifest="$(_install_os_manifest_path "$detected_os_id" "$detected_os_version")"
    parse_env_manifest "$os_manifest"

    pkg_manager="${TT_MANIFEST_SCALARS[PKG_MANAGER]:-}"
    use_ppa="${TT_MANIFEST_SCALARS[USE_PPA]:-}"

    [[ -n "$pkg_manager" ]] || fail "OS manifest is missing PKG_MANAGER: ${os_manifest}"
    [[ -n "$use_ppa" ]] || fail "OS manifest is missing USE_PPA: ${os_manifest}"

    if [[ "$pkg_manager" != "apt" ]]; then
        fail "Unsupported package manager for install: ${pkg_manager}"
    fi

    case "$use_ppa" in
        true)
            _install_apt_packages "$dry_run"
            ;;
        false)
            log_info "PPA install path is disabled by ${os_manifest}."
            ;;
        *)
            fail "Invalid USE_PPA value in ${os_manifest}: ${use_ppa}"
            ;;
    esac
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
        _install_system_packages "$dry_run"
        if [[ -e "$version_dir" && "$force" -eq 1 ]]; then
            log_info "[dry-run] Would remove existing version directory: ${version_dir}"
        fi
        log_info "[dry-run] Would create version directory: ${version_dir}"
        return 0
    fi

    mkdir -p "$versions_dir" || fail "Failed to create versions directory: ${versions_dir}"

    _install_system_packages "$dry_run"

    if [[ -e "$version_dir" && "$force" -eq 1 ]]; then
        _install_remove_version_dir "$versions_dir" "$version_dir"
    fi

    mkdir -p "$version_dir" || fail "Failed to create version directory: ${version_dir}"
    printf 'release=%s\n' "$release" >"$installed_marker" || \
        fail "Failed to write installed marker: ${installed_marker}"

    log_info "Installed release ${release} at ${version_dir}."
}
