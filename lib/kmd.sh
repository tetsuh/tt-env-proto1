#!/usr/bin/env bash
# KMD safety helpers for tt-env.
#
# Public symbols:
#   - kmd_install [package]
#   - kmd_preflight
#   - kmd_swap [module]

if [[ -n "${TT_KMD_LOADED:-}" ]]; then
    return 0
fi
TT_KMD_LOADED=1

KMD_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${KMD_LIB_DIR}/core.sh"

_kmd_require_command() {
    local command_name="$1"
    local message="$2"

    if ! command_exists "$command_name"; then
        fail "$message"
    fi
}

_kmd_run_privileged() {
    if [[ "${EUID}" -eq 0 ]]; then
        "$@"
        return
    fi

    _kmd_require_command sudo "sudo is required to install and load the KMD."
    sudo "$@"
}

_kmd_device_paths() {
    local device_glob="${TT_KMD_DEVICE_GLOB:-/dev/tenstorrent/*}"
    local device_path

    while IFS= read -r device_path; do
        [[ -n "$device_path" ]] && printf '%s\n' "$device_path"
    done < <(compgen -G "$device_glob")
}

_kmd_lsof_holders() {
    local output
    local line
    local pid=""
    local command_name=""
    local -A seen_pids=()

    output="$(lsof -F pc -- "$@" 2>/dev/null)" || {
        [[ -z "${output:-}" ]] && return 0
    }

    while IFS= read -r line; do
        case "$line" in
            p*)
                pid="${line#p}"
                command_name=""
                ;;
            c*)
                command_name="${line#c}"
                if [[ -n "$pid" && -z "${seen_pids[$pid]:-}" ]]; then
                    seen_pids[$pid]=1
                    printf '%s\t%s\n' "$pid" "${command_name:-unknown}"
                fi
                ;;
        esac
    done <<<"$output"
}

_kmd_command_for_pid() {
    local pid="$1"
    local command_name

    command_name="$(ps -p "$pid" -o comm= 2>/dev/null || true)"
    command_name="${command_name//$'\n'/ }"

    if [[ -n "$command_name" ]]; then
        printf '%s\n' "$command_name"
    else
        printf 'unknown\n'
    fi
}

_kmd_fuser_holders() {
    local output
    local pid
    local command_name
    local -A seen_pids=()

    output="$(fuser -- "$@" 2>/dev/null)" || {
        [[ -z "${output:-}" ]] && return 0
    }

    for pid in $output; do
        if [[ "$pid" =~ ^[0-9]+$ && -z "${seen_pids[$pid]:-}" ]]; then
            seen_pids[$pid]=1
            command_name="$(_kmd_command_for_pid "$pid")"
            printf '%s\t%s\n' "$pid" "$command_name"
        fi
    done
}

_kmd_report_holders() {
    local holders="$1"
    local pid
    local command_name

    log_error "Tenstorrent devices are in use; refusing KMD operation."
    while IFS=$'\t' read -r pid command_name; do
        [[ -z "$pid" ]] && continue
        log_error "PID ${pid} (${command_name:-unknown}) holds /dev/tenstorrent/*"
    done <<<"$holders"
}

_kmd_module_loaded() {
    local module="$1"

    lsmod | grep -Eq "^${module}[[:space:]]"
}

kmd_preflight() {
    local -a devices=()
    local holders=""

    mapfile -t devices < <(_kmd_device_paths)

    if [[ "${#devices[@]}" -eq 0 ]]; then
        log_info "No Tenstorrent device nodes found for KMD preflight."
        return 0
    fi

    if command_exists lsof; then
        holders="$(_kmd_lsof_holders "${devices[@]}")"
    elif command_exists fuser; then
        holders="$(_kmd_fuser_holders "${devices[@]}")"
    else
        log_error "KMD preflight requires lsof or fuser."
        return 1
    fi

    if [[ -n "$holders" ]]; then
        _kmd_report_holders "$holders"
        return 1
    fi

    log_info "KMD preflight passed: no Tenstorrent device holders found."
}

kmd_install() {
    local package="${1:-${TT_KMD_PACKAGE:-tt-kmd-dkms}}"
    local module="${TT_KMD_MODULE:-tenstorrent}"

    if [[ "$#" -gt 1 ]]; then
        fail "kmd_install accepts at most one package name."
    fi

    if [[ -z "$package" ]]; then
        fail "KMD package name is empty."
    fi

    if [[ -z "$module" ]]; then
        fail "KMD module name is empty."
    fi

    _kmd_require_command apt-get "apt-get is required to install the KMD package."
    _kmd_require_command modprobe "modprobe is required to load the Tenstorrent KMD."

    log_info "Installing KMD package: ${package}"
    _kmd_run_privileged apt-get install -y "$package" || fail "Failed to install KMD package: ${package}"

    log_info "Loading ${module} KMD module."
    _kmd_run_privileged modprobe "$module" || fail "Failed to load ${module} KMD module."

    log_info "${module} KMD module is loaded."
}

kmd_swap() {
    local module="${1:-${TT_KMD_MODULE:-tenstorrent}}"
    local was_loaded=0

    if [[ "$#" -gt 1 ]]; then
        fail "kmd_swap accepts at most one module name."
    fi

    if [[ -z "$module" ]]; then
        fail "KMD module name is empty."
    fi

    _kmd_require_command lsmod "lsmod is required to inspect loaded KMD modules."
    _kmd_require_command rmmod "rmmod is required to unload the Tenstorrent KMD."
    _kmd_require_command modprobe "modprobe is required to load the Tenstorrent KMD."

    kmd_preflight || fail "KMD preflight failed."

    if _kmd_module_loaded "$module"; then
        was_loaded=1
        log_info "Unloading ${module} KMD module."
        _kmd_run_privileged rmmod "$module" || fail "Failed to unload ${module} KMD module."
    else
        log_info "${module} KMD module is not currently loaded."
    fi

    log_info "Loading ${module} KMD module."
    if _kmd_run_privileged modprobe "$module"; then
        log_info "${module} KMD module is loaded."
        return 0
    fi

    if [[ "$was_loaded" -eq 1 ]]; then
        log_error "Failed to load ${module} KMD module; attempting rollback."
        _kmd_run_privileged modprobe "$module" || \
            fail "Failed to load ${module} KMD module and rollback also failed."
        log_error "Failed to load ${module} KMD module; rolled back to previous module."
        return 1
    fi

    fail "Failed to load ${module} KMD module."
}
