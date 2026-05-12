#!/usr/bin/env bash
# Status helpers for tt-env.
#
# Public symbols:
#   - status_show

if [[ -n "${TT_STATUS_LOADED:-}" ]]; then
    return 0
fi
TT_STATUS_LOADED=1

STATUS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${STATUS_LIB_DIR}/core.sh"

_status_usage() {
    cat <<'EOF'
Usage:
  tt-env status
EOF
}

_status_detect_hardware() {
    local vendor_id="${TT_STATUS_TT_VENDOR_ID:-1e52}"

    lspci -Dnn | grep -i "\\[${vendor_id}:" || true
}

_status_active_release() {
    local current_link="${TT_HOME}/current"
    local current_target

    if [[ ! -L "$current_link" ]]; then
        printf '(none)\n'
        return 0
    fi

    current_target="$(readlink "$current_link")" || \
        fail "Failed to read current symlink: ${current_link}"
    current_target="${current_target%/}"

    printf '%s\n' "${current_target##*/}"
}

_status_kmd_version() {
    local module="${TT_STATUS_KMD_MODULE:-tenstorrent}"
    local sys_module_dir="${TT_STATUS_SYS_MODULE_DIR:-/sys/module}"
    local version

    if [[ ! -d "${sys_module_dir}/${module}" ]]; then
        printf '(not loaded)\n'
        return 0
    fi

    if ! command_exists modinfo; then
        printf '(unknown)\n'
        return 0
    fi

    version="$(modinfo -F version "$module" 2>/dev/null)" || version=""

    if [[ -n "$version" ]]; then
        printf '%s\n' "$version"
    else
        printf '(unknown)\n'
    fi
}

_status_manifest_freshness() {
    local marker="${TT_STATUS_LAST_UPDATE_FILE:-${TT_HOME}/manifests/last_update}"
    local updated_epoch
    local now_epoch="${TT_STATUS_NOW_EPOCH:-}"
    local delta
    local minutes
    local hours

    if [[ ! -f "$marker" ]]; then
        printf '(never)\n'
        return 0
    fi

    read -r updated_epoch <"$marker" || updated_epoch=""
    if [[ ! "$updated_epoch" =~ ^[0-9]+$ ]]; then
        printf '(unknown)\n'
        return 0
    fi

    if [[ -z "$now_epoch" ]]; then
        now_epoch="$(date +%s)" || {
            printf '(unknown)\n'
            return 0
        }
    fi

    if [[ ! "$now_epoch" =~ ^[0-9]+$ ]]; then
        printf '(unknown)\n'
        return 0
    fi

    delta=$((now_epoch - updated_epoch))
    if [[ "$delta" -lt 0 ]]; then
        delta=0
    fi

    if [[ "$delta" -lt 3600 ]]; then
        minutes=$((delta / 60))
        if [[ "$minutes" -le 0 ]]; then
            printf 'less than 1 minute ago\n'
        elif [[ "$minutes" -eq 1 ]]; then
            printf '1 minute ago\n'
        else
            printf '%d minutes ago\n' "$minutes"
        fi
        return 0
    fi

    hours=$((delta / 3600))
    if [[ "$hours" -eq 1 ]]; then
        printf '1 hour ago\n'
    else
        printf '%d hours ago\n' "$hours"
    fi
}

status_show() {
    local arg
    local -a devices=()
    local device
    local active_release
    local kmd_version
    local manifest_freshness

    while [[ "$#" -gt 0 ]]; do
        arg="$1"
        case "$arg" in
            --help|-h)
                _status_usage
                return 0
                ;;
            *)
                fail "Unknown status option: ${arg}"
                ;;
        esac
        shift
    done

    if ! command_exists lspci; then
        fail "lspci is required to detect Tenstorrent hardware."
    fi

    mapfile -t devices < <(_status_detect_hardware)
    active_release="$(_status_active_release)" || return 1
    kmd_version="$(_status_kmd_version)"
    manifest_freshness="$(_status_manifest_freshness)"

    printf 'Status\n'
    printf 'Tenstorrent hardware: %d device(s)\n' "${#devices[@]}"
    printf 'Active release: %s\n' "$active_release"
    printf 'KMD module version: %s\n' "$kmd_version"
    printf 'Manifest freshness: %s\n' "$manifest_freshness"

    for device in "${devices[@]}"; do
        printf '  %s\n' "$device"
    done
}
