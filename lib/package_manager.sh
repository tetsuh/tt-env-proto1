#!/usr/bin/env bash
# Package manager helpers for tt-env installs.
#
# Public symbols:
#   - package_manager_require_supported <package-manager>
#   - package_manager_install_system_packages <package-manager> <dry-run>
#
# Callers must parse the OS manifest with parse_env_manifest before invoking
# these helpers; package resolution uses the parser globals from that manifest.

if [[ -n "${TT_PACKAGE_MANAGER_LOADED:-}" ]]; then
    return 0
fi
TT_PACKAGE_MANAGER_LOADED=1

PACKAGE_MANAGER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${PACKAGE_MANAGER_LIB_DIR}/core.sh"
# shellcheck disable=SC1091
source "${PACKAGE_MANAGER_LIB_DIR}/manifest_parser.sh"

declare -ga TT_PACKAGE_MANAGER_VIRTUAL_PACKAGES=("cmake" "ninja" "zlib" "kmd")

_package_manager_required_repos() {
    local output_ref="$1"

    # shellcheck disable=SC2034 # nameref output parameter
    local -n repos_ref="$output_ref"
    repos_ref=()

    if declare -p TT_MANIFEST_LIST_REQUIRED_REPOS >/dev/null 2>&1; then
        local -n manifest_repos=TT_MANIFEST_LIST_REQUIRED_REPOS
        # shellcheck disable=SC2034 # nameref output parameter
        repos_ref=("${manifest_repos[@]}")
    fi
}

_package_manager_resolved_packages() {
    local output_ref="$1"
    local virtual_package
    local resolved_package

    # shellcheck disable=SC2034 # nameref output parameter
    local -n packages_ref="$output_ref"
    packages_ref=()

    for virtual_package in "${TT_PACKAGE_MANAGER_VIRTUAL_PACKAGES[@]}"; do
        if ! resolved_package="$(resolve_package "$virtual_package")"; then
            fail "Failed to resolve package from OS manifest: ${virtual_package}"
        fi
        # shellcheck disable=SC2034 # nameref output parameter
        packages_ref+=("$resolved_package")
    done

    if [[ "${#packages_ref[@]}" -eq 0 ]]; then
        fail "No packages resolved from OS manifest."
    fi
}

package_manager_require_supported() {
    local pkg_manager="$1"

    case "$pkg_manager" in
        apt|dnf)
            ;;
        *)
            fail "Unsupported package manager for install: ${pkg_manager}"
            ;;
    esac
}

_package_manager_require_sudo() {
    local pkg_manager="$1"

    if ! command_exists sudo; then
        fail "sudo is required to install ${pkg_manager} packages. Install sudo or run on a system where sudo is available."
    fi
}

_package_manager_require_apt_tools() {
    local repo_count="$1"

    if ! command_exists apt-get; then
        fail "apt-get is required to install apt packages."
    fi

    if [[ "$repo_count" -gt 0 ]] && ! command_exists add-apt-repository; then
        fail "add-apt-repository is required to add repositories. Install software-properties-common."
    fi
}

_package_manager_apt_install_system_packages() {
    local dry_run="$1"
    local -a repos=()
    local -a packages=()
    local repo

    _package_manager_required_repos repos
    _package_manager_resolved_packages packages

    if [[ "$dry_run" -eq 1 ]]; then
        for repo in "${repos[@]}"; do
            log_info "[dry-run] Would add apt repository: ${repo}"
        done
        log_info "[dry-run] Would run apt-get update."
        log_info "[dry-run] Would install apt packages: ${packages[*]}"
        return 0
    fi

    _package_manager_require_sudo apt
    _package_manager_require_apt_tools "${#repos[@]}"

    for repo in "${repos[@]}"; do
        log_info "Adding apt repository: ${repo}"
        sudo add-apt-repository -y "$repo" || fail "Failed to add repository: ${repo}"
    done

    log_info "Updating apt package metadata."
    sudo apt-get update || fail "Failed to update apt package metadata."

    log_info "Installing apt packages: ${packages[*]}"
    sudo apt-get install -y "${packages[@]}" || fail "Failed to install apt packages."
}

_package_manager_require_dnf_tools() {
    if ! command_exists dnf; then
        fail "dnf is required to install dnf packages."
    fi
}

_package_manager_dnf_install_system_packages() {
    local dry_run="$1"
    local -a repos=()
    local -a packages=()
    local repo

    _package_manager_required_repos repos
    _package_manager_resolved_packages packages

    if [[ "$dry_run" -eq 1 ]]; then
        for repo in "${repos[@]}"; do
            log_info "[dry-run] Would add dnf repository: ${repo}"
        done
        log_info "[dry-run] Would run dnf makecache."
        log_info "[dry-run] Would install dnf packages: ${packages[*]}"
        return 0
    fi

    _package_manager_require_sudo dnf
    _package_manager_require_dnf_tools

    for repo in "${repos[@]}"; do
        log_info "Adding dnf repository: ${repo}"
        sudo dnf config-manager --add-repo "$repo" || fail "Failed to add repository: ${repo}"
    done

    log_info "Updating dnf package metadata."
    sudo dnf makecache || fail "Failed to update dnf package metadata."

    log_info "Installing dnf packages: ${packages[*]}"
    sudo dnf install -y "${packages[@]}" || fail "Failed to install dnf packages."
}

package_manager_install_system_packages() {
    local pkg_manager="$1"
    local dry_run="$2"

    case "$pkg_manager" in
        apt)
            _package_manager_apt_install_system_packages "$dry_run"
            ;;
        dnf)
            _package_manager_dnf_install_system_packages "$dry_run"
            ;;
        *)
            fail "Unsupported package manager for install: ${pkg_manager}"
            ;;
    esac
}
