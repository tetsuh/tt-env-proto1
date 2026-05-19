#!/usr/bin/env bash
# Shim generation helpers for tt-env.
#
# Public symbols:
#   - TT_SHIM_COMMANDS
#   - list_known_shims
#   - generate_shims
#
# Known shim commands:
#   - tt-smi
#   - tt-flash
#   - tt-topology
#   - tt-burnin
#   - tt-inference-server
#   - tt-metalium
#   - tt-metalium-models
#   - tt-studio

if [[ -n "${TT_SHIMS_LOADED:-}" ]]; then
    return 0
fi
TT_SHIMS_LOADED=1

SHIMS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SHIMS_LIB_DIR}/core.sh"

declare -ga TT_SHIM_COMMANDS=(
    "tt-smi"
    "tt-flash"
    "tt-topology"
    "tt-burnin"
    "tt-inference-server"
    "tt-metalium"
    "tt-metalium-models"
    "tt-studio"
)
declare -ga TT_OPTIONAL_SHIM_COMMANDS=(
    "tt-burnin"
    "tt-inference-server"
    "tt-metalium"
    "tt-metalium-models"
    "tt-studio"
)

list_known_shims() {
    printf '%s\n' "${TT_SHIM_COMMANDS[@]}"
}

shim_command_is_optional() {
    local command_name="$1"
    local optional_command

    for optional_command in "${TT_OPTIONAL_SHIM_COMMANDS[@]}"; do
        [[ "$command_name" == "$optional_command" ]] && return 0
    done

    return 1
}

_write_shim() {
    local shim_path="$1"

    cat >"$shim_path" <<'EOF' || fail "Failed to write shim: ${shim_path}"
#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${TT_HOME:-}" ]]; then
  if [[ -z "${HOME:-}" ]]; then
    printf '[ERROR] HOME environment variable is not set.\n' >&2
    exit 1
  fi
  TT_HOME="${HOME}/.tt-env"
fi
export TT_HOME

command_name="${0##*/}"
target="${TT_HOME}/current/bin/${command_name}"

if [[ ! -x "$target" ]]; then
  printf '[ERROR] Active tt-env command not found or not executable: %s\n' "$target" >&2
  exit 1
fi

exec "$target" "$@"
EOF
    chmod 755 "$shim_path" || fail "Failed to make shim executable: ${shim_path}"
}

generate_shims() {
    local shim_dir
    local command_name

    init_tt_home
    shim_dir="${TT_HOME}/shims"

    for command_name in "${TT_SHIM_COMMANDS[@]}"; do
        _write_shim "${shim_dir}/${command_name}"
    done

    log_info "Generated ${#TT_SHIM_COMMANDS[@]} shims in ${shim_dir}."
}
