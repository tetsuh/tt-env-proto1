#!/usr/bin/env bash
# Restricted manifest parsers for tt-env.
#
# OS .env grammar accepted by parse_env_manifest:
#   - blank lines and comment lines beginning with '#'
#   - KEY="VALUE" scalar assignments
#   - KEY=() empty arrays
#   - KEY=("VALUE" VALUE) single-line arrays
#   - KEY=( followed by item lines and a line containing only )
#
# Keys must match [A-Z_][A-Z0-9_]*. Values are literal tokens containing only
# alnum, underscore, dot, slash, colon, plus, or dash. This parser never sources
# manifest files.

if [[ -n "${TT_MANIFEST_PARSER_LOADED:-}" ]]; then
    return 0
fi
TT_MANIFEST_PARSER_LOADED=1

MANIFEST_PARSER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${MANIFEST_PARSER_DIR}/core.sh"

declare -gA TT_MANIFEST_SCALARS=()
declare -ga TT_MANIFEST_LIST_KEYS=()

_manifest_is_key() {
    [[ "$1" =~ ^[A-Z_][A-Z0-9_]*$ ]]
}

_manifest_has_dangerous_chars() {
    [[ "$1" == *"\$("* || "$1" == *"\`"* || "$1" == *";"* || "$1" == *"\$"* || "$1" == *"\\"* ]]
}

_manifest_reset_env_state() {
    local key
    for key in "${TT_MANIFEST_LIST_KEYS[@]}"; do
        unset -v "TT_MANIFEST_LIST_${key}"
    done

    TT_MANIFEST_SCALARS=()
    TT_MANIFEST_LIST_KEYS=()
}

_manifest_init_list() {
    local key="$1"
    local array_name="TT_MANIFEST_LIST_${key}"

    _manifest_is_key "$key" || fail "Invalid manifest key: ${key}"
    unset -v "$array_name"
    declare -g -a "$array_name"
    TT_MANIFEST_LIST_KEYS+=("$key")
}

_manifest_append_list_value() {
    local key="$1"
    local value="$2"
    local array_name="TT_MANIFEST_LIST_${key}"

    _manifest_is_key "$key" || fail "Invalid manifest key: ${key}"
    local -n list_ref="$array_name"
    list_ref+=("$value")
}

_manifest_parse_list_tokens() {
    local key="$1"
    local text="$2"
    local value

    while [[ -n "$text" ]]; do
        if [[ "$text" =~ ^[[:space:]]+(.+)$ ]]; then
            text="${BASH_REMATCH[1]}"
        elif [[ "$text" =~ ^# ]]; then
            break
        elif [[ "$text" =~ ^\"([A-Za-z0-9_./:+-]*)\"(.*)$ ]]; then
            value="${BASH_REMATCH[1]}"
            text="${BASH_REMATCH[2]}"
            _manifest_append_list_value "$key" "$value"
        elif [[ "$text" =~ ^([A-Za-z0-9_./:+-]+)(.*)$ ]]; then
            value="${BASH_REMATCH[1]}"
            text="${BASH_REMATCH[2]}"
            _manifest_append_list_value "$key" "$value"
        else
            fail "Invalid manifest list item for ${key}: ${text}"
        fi
    done
}

parse_env_manifest() {
    local manifest_file="$1"
    local line
    local line_no=0
    local in_array_key=""
    local key
    local value
    local list_body

    [[ -f "$manifest_file" ]] || fail "Manifest file not found: ${manifest_file}"
    _manifest_reset_env_state

    while IFS= read -r line || [[ -n "$line" ]]; do
        line_no=$((line_no + 1))
        line="${line%$'\r'}"

        if [[ "$line" =~ ^[[:space:]]*$ || "$line" =~ ^[[:space:]]*# ]]; then
            continue
        fi

        if _manifest_has_dangerous_chars "$line"; then
            fail "Rejected unsafe manifest line ${line_no}: ${line}"
        fi

        if [[ -n "$in_array_key" ]]; then
            if [[ "$line" =~ ^[[:space:]]*\)[[:space:]]*$ ]]; then
                in_array_key=""
            elif [[ "$line" =~ ^[[:space:]]*(.*[^[:space:]])[[:space:]]*$ ]]; then
                _manifest_parse_list_tokens "$in_array_key" "${BASH_REMATCH[1]}"
            else
                fail "Invalid manifest array line ${line_no}: ${line}"
            fi
            continue
        fi

        if [[ "$line" =~ ^[[:space:]]*([A-Z_][A-Z0-9_]*)=\"([A-Za-z0-9_./:+-]*)\"[[:space:]]*$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            # shellcheck disable=SC2034
            TT_MANIFEST_SCALARS["$key"]="$value"
        elif [[ "$line" =~ ^[[:space:]]*([A-Z_][A-Z0-9_]*)=\([[:space:]]*\)[[:space:]]*$ ]]; then
            key="${BASH_REMATCH[1]}"
            _manifest_init_list "$key"
        elif [[ "$line" =~ ^[[:space:]]*([A-Z_][A-Z0-9_]*)=\([[:space:]]*(.*[^[:space:]])[[:space:]]*\)[[:space:]]*$ ]]; then
            key="${BASH_REMATCH[1]}"
            list_body="${BASH_REMATCH[2]}"
            _manifest_init_list "$key"
            _manifest_parse_list_tokens "$key" "$list_body"
        elif [[ "$line" =~ ^[[:space:]]*([A-Z_][A-Z0-9_]*)=\([[:space:]]*$ ]]; then
            key="${BASH_REMATCH[1]}"
            _manifest_init_list "$key"
            in_array_key="$key"
        else
            fail "Invalid manifest line ${line_no}: ${line}"
        fi
    done <"$manifest_file"

    if [[ -n "$in_array_key" ]]; then
        fail "Unterminated manifest array: ${in_array_key}"
    fi
}
