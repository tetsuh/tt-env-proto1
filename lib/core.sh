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
