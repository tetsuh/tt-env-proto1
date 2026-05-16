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

_package_manager_os_release_field() {
    local field="$1"
    local value="" line
    while IFS= read -r line || [[ -n "$line" ]]; do
        case "$line" in
            "${field}"=*)
                value="${line#"${field}"=}"
                value="${value%$'\r'}"
                value="${value%\"}"
                value="${value#\"}"
                ;;
        esac
    done </etc/os-release
    printf '%s' "$value"
}

_package_manager_apt_add_repo_tenstorrent() {
    local ubuntu_codename deb_url source_file key_file

    ubuntu_codename="$(_package_manager_os_release_field UBUNTU_CODENAME)"
    [[ -n "$ubuntu_codename" ]] || ubuntu_codename="$(_package_manager_os_release_field VERSION_CODENAME)"

    [[ -n "$ubuntu_codename" ]] || \
        fail "Could not determine apt repository codename from /etc/os-release"

    deb_url="https://ppa.tenstorrent.com/ubuntu/"
    source_file="/etc/apt/sources.list.d/tenstorrent.list"
    key_file="/etc/apt/keyrings/tt-pkg-key.asc"

    sudo mkdir -p /etc/apt/keyrings
    if command_exists curl; then
        curl -fsSL "https://ppa.tenstorrent.com/ubuntu/tt-pkg-key.asc" | sudo tee "$key_file" >/dev/null || fail "Failed to download Tenstorrent GPG key"
    else
        fail "curl is required to download Tenstorrent GPG key"
    fi

    echo "deb [signed-by=${key_file}] ${deb_url} ${ubuntu_codename} main" | sudo tee "$source_file" >/dev/null
}

# On Linux Mint, /usr/bin/add-apt-repository is Mint's mintSources.py wrapper,
# which validates ppa: repos against the Launchpad API before adding them. This
# fails when the PPA is not yet published on Launchpad. Work around this by
# directly constructing the deb source line using UBUNTU_CODENAME from
# /etc/os-release, bypassing the mintSources.py Launchpad check.
_package_manager_apt_add_repo_mint() {
    local repo="$1"
    local ubuntu_codename ppa_path ppa_owner ppa_name
    local deb_url source_file key_file fingerprint deb_line

    if [[ "$repo" != ppa:* ]]; then
        sudo add-apt-repository -y "$repo" || fail "Failed to add repository: ${repo}"
        return
    fi

    ubuntu_codename="$(_package_manager_os_release_field UBUNTU_CODENAME)"
    [[ -n "$ubuntu_codename" ]] || \
        fail "UBUNTU_CODENAME not set in /etc/os-release; cannot add PPA on Linux Mint."

    ppa_path="${repo#ppa:}"
    ppa_owner="${ppa_path%%/*}"
    ppa_name="${ppa_path#*/}"
    [[ "$ppa_name" != "$ppa_owner" && -n "$ppa_name" ]] || ppa_name="ppa"

    deb_url="https://ppa.launchpadcontent.net/${ppa_owner}/${ppa_name}/ubuntu"
    source_file="/etc/apt/sources.list.d/${ppa_owner}-${ppa_name}-${ubuntu_codename}.list"
    key_file="/etc/apt/keyrings/${ppa_owner}-${ppa_name}-${ubuntu_codename}.gpg"

    fingerprint=""
    if command_exists curl && command_exists python3; then
        fingerprint="$(curl -sf \
            "https://launchpad.net/api/1.0/~${ppa_owner}/+archive/${ppa_name}" \
            | python3 -c \
            "import json,sys; print(json.load(sys.stdin).get('signing_key_fingerprint',''))" \
            2>/dev/null)" || fingerprint=""
    fi

    if [[ -n "${fingerprint:-}" ]]; then
        sudo mkdir -p /etc/apt/keyrings
        if sudo gpg --keyserver hkps://keyserver.ubuntu.com --recv-keys "$fingerprint" 2>/dev/null \
                && sudo gpg --export "$fingerprint" | sudo tee "$key_file" >/dev/null; then
            deb_line="deb [signed-by=${key_file}] ${deb_url} ${ubuntu_codename} main"
        else
            log_info "Warning: could not import GPG key for ${repo}; repository will be unsigned."
            deb_line="deb ${deb_url} ${ubuntu_codename} main"
        fi
    else
        log_info "Warning: could not retrieve GPG key for ${repo} from Launchpad; repository will be unsigned."
        deb_line="deb ${deb_url} ${ubuntu_codename} main"
    fi

    printf '%s\n' "$deb_line" | sudo tee "$source_file" >/dev/null \
        || fail "Failed to add repository: ${repo}"
    log_info "Added apt repository source: ${deb_line}"
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
        if [[ "$repo" == "https://ppa.tenstorrent.com/ubuntu/" || "$repo" == "ppa:tenstorrent/ppa" ]]; then
            _package_manager_apt_add_repo_tenstorrent
        elif [[ "${OS_ID:-}" == "linuxmint" ]]; then
            _package_manager_apt_add_repo_mint "$repo"
        else
            sudo add-apt-repository -y "$repo" || fail "Failed to add repository: ${repo}"
        fi
    done

    log_info "Updating apt package metadata."
    sudo apt-get update || fail "Failed to update apt package metadata."

    log_info "Installing apt packages: ${packages[*]}"
    sudo apt-get install -y "${packages[@]}" || fail "Failed to install apt packages."
}

_package_manager_require_dnf_tools() {
    local repo_count="$1"

    if ! command_exists dnf; then
        fail "dnf is required to install dnf packages."
    fi

    if [[ "$repo_count" -gt 0 ]] && ! dnf config-manager --help >/dev/null 2>&1; then
        fail "dnf config-manager is required to add repositories. Install dnf-plugins-core."
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
    _package_manager_require_dnf_tools "${#repos[@]}"

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
