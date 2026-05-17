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

declare -gar TT_PACKAGE_MANAGER_VIRTUAL_PACKAGES=("cmake" "ninja" "zlib" "kmd" "smi" "flash" "topology")
declare -gr TT_TENSTORRENT_APT_REPO_URL="https://ppa.tenstorrent.com/ubuntu"
declare -gr TT_TENSTORRENT_APT_KEY_URL="https://ppa.tenstorrent.com/tt-pkg-key.asc"
declare -gr TT_TENSTORRENT_APT_KEY_FINGERPRINT="58540CD771C55DD7C33030CA8A9D565F6A208463"
declare -gr TT_TENSTORRENT_APT_KEYRING="/etc/apt/keyrings/tt-pkg-key.asc"
declare -gr TT_TENSTORRENT_APT_SOURCE="/etc/apt/sources.list.d/tenstorrent.list"

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

_package_manager_normalized_repo() {
    local repo="$1"

    repo="${repo%$'\r'}"
    repo="${repo%"${repo##*[![:space:]]}"}"
    repo="${repo#"${repo%%[![:space:]]*}"}"
    repo="${repo%/}"
    printf '%s\n' "$repo"
}

_package_manager_is_tenstorrent_apt_repo() {
    local repo

    repo="$(_package_manager_normalized_repo "$1")"
    [[ "$repo" == "$TT_TENSTORRENT_APT_REPO_URL" ]]
}

_package_manager_needs_add_apt_repository() {
    local repo

    for repo in "$@"; do
        if ! _package_manager_is_tenstorrent_apt_repo "$repo"; then
            return 0
        fi
    done

    return 1
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
    local needs_add_apt_repository="$1"

    if ! command_exists apt-get; then
        fail "apt-get is required to install apt packages."
    fi

    if [[ "$needs_add_apt_repository" -eq 1 ]] && ! command_exists add-apt-repository; then
        fail "add-apt-repository is required to add repositories. Install software-properties-common."
    fi
}

_package_manager_os_release_field() {
    local field="$1"
    local os_release_file="${TT_OS_RELEASE_FILE:-/etc/os-release}"
    local line
    local value=""

    if [[ ! -f "$os_release_file" ]]; then
        fail "Cannot determine apt repository codename: ${os_release_file} not found."
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        case "$line" in
            "${field}"=*)
                value="${line#*=}"
                value="${value%$'\r'}"
                value="${value%\"}"
                value="${value#\"}"
                value="${value%\'}"
                value="${value#\'}"
                break
                ;;
        esac
    done <"$os_release_file"

    printf '%s\n' "$value"
}

_package_manager_tenstorrent_codename() {
    local codename

    codename="$(_package_manager_os_release_field UBUNTU_CODENAME)"
    if [[ -z "$codename" ]]; then
        codename="$(_package_manager_os_release_field VERSION_CODENAME)"
    fi

    case "$codename" in
        jammy|noble)
            printf '%s\n' "$codename"
            ;;
        "")
            fail "Cannot determine Tenstorrent apt repository codename from ${TT_OS_RELEASE_FILE:-/etc/os-release}; expected UBUNTU_CODENAME or VERSION_CODENAME for supported codenames: jammy, noble."
            ;;
        *)
            fail "Unsupported Tenstorrent apt repository codename '${codename}' from ${TT_OS_RELEASE_FILE:-/etc/os-release}; supported codenames: jammy, noble."
            ;;
    esac
}

_package_manager_verify_tenstorrent_key() {
    local key_file="$1"
    local actual_fingerprint=""

    unset TT_TENSTORRENT_APT_KEY_VERIFY_ERROR

    if ! command_exists gpg; then
        TT_TENSTORRENT_APT_KEY_VERIFY_ERROR="gpg is required to verify the Tenstorrent apt signing key."
        return 1
    fi

    while IFS=: read -r record_type _ _ _ _ _ _ _ _ fingerprint _; do
        if [[ "$record_type" == "fpr" ]]; then
            actual_fingerprint="$fingerprint"
            break
        fi
    done < <(gpg --batch --show-keys --with-colons "$key_file" 2>/dev/null)

    if [[ "$actual_fingerprint" != "$TT_TENSTORRENT_APT_KEY_FINGERPRINT" ]]; then
        TT_TENSTORRENT_APT_KEY_VERIFY_ERROR="Tenstorrent apt signing key fingerprint mismatch: expected ${TT_TENSTORRENT_APT_KEY_FINGERPRINT}, got ${actual_fingerprint:-unknown}."
        return 1
    fi
}

_package_manager_tenstorrent_deb_line() {
    local codename="$1"

    printf 'deb [arch=amd64 signed-by=%s] %s/ %s main\n' \
        "$TT_TENSTORRENT_APT_KEYRING" \
        "$TT_TENSTORRENT_APT_REPO_URL" \
        "$codename"
}

_package_manager_apt_add_tenstorrent_repo() {
    local codename
    local deb_line
    local key_error
    local key_tmp

    codename="$(_package_manager_tenstorrent_codename)"
    deb_line="$(_package_manager_tenstorrent_deb_line "$codename")"

    command_exists curl || fail "curl is required to download the Tenstorrent apt signing key."

    key_tmp="$(mktemp)" || fail "Failed to create temporary file for Tenstorrent apt signing key."

    curl --fail --location --silent --show-error --output "$key_tmp" "$TT_TENSTORRENT_APT_KEY_URL" || \
        {
            rm -f -- "$key_tmp"
            fail "Failed to download Tenstorrent apt signing key from ${TT_TENSTORRENT_APT_KEY_URL}."
        }
    if ! _package_manager_verify_tenstorrent_key "$key_tmp"; then
        key_error="${TT_TENSTORRENT_APT_KEY_VERIFY_ERROR:-Failed to verify Tenstorrent apt signing key.}"
        rm -f -- "$key_tmp"
        fail "$key_error"
    fi

    sudo install -d -m 0755 /etc/apt/keyrings || {
        rm -f -- "$key_tmp"
        fail "Failed to create apt keyring directory."
    }
    sudo install -m 0644 "$key_tmp" "$TT_TENSTORRENT_APT_KEYRING" || \
        {
            rm -f -- "$key_tmp"
            fail "Failed to install Tenstorrent apt signing key."
        }
    printf '%s\n' "$deb_line" | sudo tee "$TT_TENSTORRENT_APT_SOURCE" >/dev/null || \
        {
            rm -f -- "$key_tmp"
            fail "Failed to add Tenstorrent apt repository source."
        }

    rm -f -- "$key_tmp"
}

_package_manager_apt_dry_run_repo() {
    local repo="$1"
    local codename
    local deb_line

    if _package_manager_is_tenstorrent_apt_repo "$repo"; then
        codename="$(_package_manager_tenstorrent_codename)"
        deb_line="$(_package_manager_tenstorrent_deb_line "$codename")"
        log_info "[dry-run] Would create apt keyring directory: /etc/apt/keyrings"
        log_info "[dry-run] Would download Tenstorrent apt signing key: ${TT_TENSTORRENT_APT_KEY_URL}"
        log_info "[dry-run] Would verify Tenstorrent apt signing key fingerprint: ${TT_TENSTORRENT_APT_KEY_FINGERPRINT}"
        log_info "[dry-run] Would write apt source ${TT_TENSTORRENT_APT_SOURCE}: ${deb_line}"
    else
        log_info "[dry-run] Would add apt repository: ${repo}"
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
            _package_manager_apt_dry_run_repo "$repo"
        done
        log_info "[dry-run] Would run apt-get update."
        log_info "[dry-run] Would install apt packages: ${packages[*]}"
        return 0
    fi

    _package_manager_require_sudo apt
    if _package_manager_needs_add_apt_repository "${repos[@]}"; then
        _package_manager_require_apt_tools 1
    else
        _package_manager_require_apt_tools 0
    fi

    for repo in "${repos[@]}"; do
        log_info "Adding apt repository: ${repo}"
        if _package_manager_is_tenstorrent_apt_repo "$repo"; then
            _package_manager_apt_add_tenstorrent_repo
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
