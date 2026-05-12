#!/usr/bin/env bash
# KMD safety helpers for tt-env.
#
# Public symbols:
#   - kmd_preflight

if [[ -n "${TT_KMD_LOADED:-}" ]]; then
    return 0
fi
TT_KMD_LOADED=1

KMD_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${KMD_LIB_DIR}/core.sh"

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
                if [[ -n "$pid" ]]; then
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
    local device_path
    local output
    local pid
    local command_name
    local -A seen_pids=()

    for device_path in "$@"; do
        output="$(fuser -- "$device_path" 2>/dev/null)" || {
            [[ -z "${output:-}" ]] && continue
        }

        for pid in $output; do
            if [[ "$pid" =~ ^[0-9]+$ && -z "${seen_pids[$pid]:-}" ]]; then
                seen_pids[$pid]=1
                command_name="$(_kmd_command_for_pid "$pid")"
                printf '%s\t%s\n' "$pid" "$command_name"
            fi
        done
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
