#!/usr/bin/env bash
# lib/core.sh
# Core helpers for tt-env
#
# Public symbols:
#   - log_info <message>
#   - log_warn <message>
#   - log_error <message>
#   - fail <message>
#   - command_exists <command>
#   - detect_os [os-release-file]
#   - init_tt_home

# Color definitions
# Use tput if available and attached to a tty
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
    TT_COLOR_INFO=$(tput setaf 6)    # Cyan
    TT_COLOR_WARN=$(tput setaf 3)    # Yellow
    TT_COLOR_ERROR=$(tput setaf 1)   # Red
    TT_COLOR_RESET=$(tput sgr0)      # Reset
else
    TT_COLOR_INFO=""
    TT_COLOR_WARN=""
    TT_COLOR_ERROR=""
    TT_COLOR_RESET=""
fi

log_info() {
    printf '%s %s\n' "${TT_COLOR_INFO}[INFO]${TT_COLOR_RESET}" "$*"
}

log_warn() {
    printf '%s %s\n' "${TT_COLOR_WARN}[WARN]${TT_COLOR_RESET}" "$*" >&2
}

log_error() {
    printf '%s %s\n' "${TT_COLOR_ERROR}[ERROR]${TT_COLOR_RESET}" "$*" >&2
}

fail() {
    log_error "$*"
    exit 1
}

command_exists() {
    command -v -- "$1" >/dev/null 2>&1
}

init_tt_home() {
    if [[ -z "${TT_HOME:-}" ]]; then
        [[ -z "${HOME:-}" ]] && fail "HOME environment variable is not set."
        TT_HOME="${HOME}/.tt-env"
    fi
    export TT_HOME

    mkdir -p "${TT_HOME}/"{bin,lib,manifests,releases,versions,shims,keys} || \
        fail "Failed to initialize TT_HOME directory layout at ${TT_HOME}"
}

detect_os() {
    local os_release_file="${1:-/etc/os-release}"
    local os_id=""
    local os_version=""
    local line
    local key
    local value

    if [[ -n "${TT_OVERRIDE_OS_ID:-}" || -n "${TT_OVERRIDE_OS_VERSION:-}" ]]; then
        if [[ -z "${TT_OVERRIDE_OS_ID:-}" || -z "${TT_OVERRIDE_OS_VERSION:-}" ]]; then
            fail "Both TT_OVERRIDE_OS_ID and TT_OVERRIDE_OS_VERSION must be set for OS override."
        fi

        OS_ID="${TT_OVERRIDE_OS_ID}"
        OS_VERSION="${TT_OVERRIDE_OS_VERSION}"
        export OS_ID OS_VERSION
        log_info "Using override OS: ${OS_ID} ${OS_VERSION}"
        return 0
    fi

    if [[ ! -f "$os_release_file" ]]; then
        fail "Cannot detect OS: ${os_release_file} not found."
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        case "$line" in
            ID=*|VERSION_ID=*)
                key="${line%%=*}"
                value="${line#*=}"
                value="${value%$'\r'}"
                value="${value%\"}"
                value="${value#\"}"
                value="${value%\'}"
                value="${value#\'}"

                case "$key" in
                    ID)
                        os_id="$value"
                        ;;
                    VERSION_ID)
                        os_version="$value"
                        ;;
                esac
                ;;
        esac
    done <"$os_release_file"

    if [[ -z "$os_id" || -z "$os_version" ]]; then
        fail "Cannot detect OS: ${os_release_file} is missing ID or VERSION_ID."
    fi

    OS_ID="$os_id"
    OS_VERSION="$os_version"
    export OS_ID OS_VERSION
}
