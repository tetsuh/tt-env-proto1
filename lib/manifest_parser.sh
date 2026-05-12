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
# manifest files. This parser also never invokes source or "."; callers load
# helper libraries before loading this file.
#
# Public symbols:
#   - parse_env_manifest <manifest-file>
#   - resolve_package <virtual-package-name>
#   - parse_stack_manifest <manifest-file>
#   - validate_stack_manifest
#
# Stack manifest components may be either:
#   - "component": "version"
#   - "component": {
#       "version": "version",
#       "download_url": "https://example.invalid/artifact",
#       "sha256": "<64 hex chars>"
#     }

if [[ -n "${TT_MANIFEST_PARSER_LOADED:-}" ]]; then
    return 0
fi
TT_MANIFEST_PARSER_LOADED=1

if ! declare -F fail >/dev/null; then
    fail() {
        printf '[ERROR] %s\n' "$*" >&2
        exit 1
    }
fi

if ! declare -F command_exists >/dev/null; then
    command_exists() {
        command -v -- "$1" >/dev/null 2>&1
    }
fi

declare -gA TT_MANIFEST_SCALARS=()
declare -ga TT_MANIFEST_LIST_KEYS=()
declare -g TT_STACK_RELEASE=""
declare -g TT_STACK_DESCRIPTION=""
declare -gA TT_STACK_COMPONENTS=()
declare -gA TT_STACK_COMPONENT_DOWNLOAD_URLS=()
declare -gA TT_STACK_COMPONENT_SHA256S=()
declare -ga TT_REQUIRED_STACK_COMPONENTS=("tt-kmd" "tt-smi" "firmware" "tt-metal")

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

_manifest_validate_workarounds() {
    if declare -p TT_MANIFEST_LIST_WORKAROUNDS >/dev/null 2>&1; then
        local -a workarounds=("${TT_MANIFEST_LIST_WORKAROUNDS[@]+"${TT_MANIFEST_LIST_WORKAROUNDS[@]}"}")
        [[ "${#workarounds[@]}" -gt 0 ]] || return 0
        declare -F validate_workarounds >/dev/null || \
            fail "validate_workarounds is required to validate WORKAROUNDS entries."
        validate_workarounds "${workarounds[@]}"
    fi
}

_stack_reset_state() {
    TT_STACK_RELEASE=""
    TT_STACK_DESCRIPTION=""
    TT_STACK_COMPONENTS=()
    TT_STACK_COMPONENT_DOWNLOAD_URLS=()
    TT_STACK_COMPONENT_SHA256S=()
}

_stack_is_sha256() {
    [[ "$1" =~ ^[A-Fa-f0-9]{64}$ ]]
}

_stack_store_component_object() {
    local key="$1"
    local version="$2"
    local download_url="$3"
    local sha256="$4"
    local line_no="$5"

    [[ -n "$version" ]] || fail "Missing stack component version for ${key} at line ${line_no}"
    [[ -n "$download_url" ]] || fail "Missing stack component download_url for ${key} at line ${line_no}"
    [[ -n "$sha256" ]] || fail "Missing stack component sha256 for ${key} at line ${line_no}"
    _stack_is_sha256 "$sha256" || fail "Invalid stack component sha256 for ${key} at line ${line_no}"

    # shellcheck disable=SC2034
    TT_STACK_COMPONENTS["$key"]="$version"
    # shellcheck disable=SC2034
    TT_STACK_COMPONENT_DOWNLOAD_URLS["$key"]="$download_url"
    # shellcheck disable=SC2034
    TT_STACK_COMPONENT_SHA256S["$key"]="$sha256"
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

    _manifest_validate_workarounds
}

resolve_package() {
    local virtual_name="${1:-}"
    local lookup_name
    local key

    [[ -n "$virtual_name" ]] || fail "resolve_package requires a virtual package name."

    lookup_name="${virtual_name^^}"
    lookup_name="${lookup_name//[-.+]/_}"
    key="VIRT_PKG_${lookup_name}"

    _manifest_is_key "$key" || fail "Invalid virtual package name: ${virtual_name}"

    if [[ -z "${TT_MANIFEST_SCALARS[$key]+x}" || -z "${TT_MANIFEST_SCALARS[$key]}" ]]; then
        fail "Virtual package is not defined: ${virtual_name} (${key})"
    fi

    printf '%s\n' "${TT_MANIFEST_SCALARS[$key]}"
}

_parse_stack_manifest_with_jq() {
    local manifest_file="$1"
    local component_key
    local component_value
    local component_download_url
    local component_sha256

    jq -e '
        def component_ok:
            (type == "string") or
            (type == "object" and
                ((keys - ["version", "download_url", "sha256"]) | length == 0) and
                (.version | type == "string" and length > 0) and
                (.download_url | type == "string" and length > 0) and
                (.sha256 | type == "string" and test("^[A-Fa-f0-9]{64}$")));

        type == "object" and
        ((has("release") | not) or (.release | type == "string")) and
        ((has("description") | not) or (.description | type == "string")) and
        ((has("components") | not) or
            (.components | type == "object" and all(.[]; component_ok))) and
        ((keys - ["release", "description", "components"]) | length == 0)
    ' "$manifest_file" >/dev/null || fail "Unsupported stack manifest shape: ${manifest_file}"

    TT_STACK_RELEASE="$(jq -r '.release // ""' "$manifest_file")"
    TT_STACK_DESCRIPTION="$(jq -r '.description // ""' "$manifest_file")"
    TT_STACK_RELEASE="${TT_STACK_RELEASE%$'\r'}"
    TT_STACK_DESCRIPTION="${TT_STACK_DESCRIPTION%$'\r'}"

    while IFS=$'\t' read -r component_key component_value component_download_url component_sha256; do
        component_key="${component_key%$'\r'}"
        component_value="${component_value%$'\r'}"
        component_download_url="${component_download_url%$'\r'}"
        component_sha256="${component_sha256%$'\r'}"
        [[ -n "$component_key" ]] || continue
        TT_STACK_COMPONENTS["$component_key"]="$component_value"
        if [[ -n "$component_download_url" || -n "$component_sha256" ]]; then
            # shellcheck disable=SC2034
            TT_STACK_COMPONENT_DOWNLOAD_URLS["$component_key"]="$component_download_url"
            # shellcheck disable=SC2034
            TT_STACK_COMPONENT_SHA256S["$component_key"]="$component_sha256"
        fi
    done < <(jq -r '
        .components // {} |
        to_entries[] |
        [
            .key,
            (if (.value | type) == "string" then .value else .value.version end),
            (if (.value | type) == "object" then .value.download_url else "" end),
            (if (.value | type) == "object" then .value.sha256 else "" end)
        ] |
        @tsv
    ' "$manifest_file")
}

_parse_stack_manifest_fallback() {
    local manifest_file="$1"
    local line
    local line_no=0
    local saw_open=0
    local saw_close=0
    local in_components=0
    local in_component_object=0
    local key
    local value
    local component_object_key=""
    local component_version=""
    local component_download_url=""
    local component_sha256=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        line_no=$((line_no + 1))
        line="${line%$'\r'}"

        if [[ "$line" =~ ^[[:space:]]*$ ]]; then
            continue
        fi

        if [[ "$saw_open" -eq 0 ]]; then
            if [[ "$line" =~ ^[[:space:]]*\{[[:space:]]*$ ]]; then
                saw_open=1
                continue
            fi
            fail "Unsupported stack manifest shape at line ${line_no}: ${line}"
        fi

        if [[ "$in_component_object" -eq 1 ]]; then
            if [[ "$line" =~ ^[[:space:]]*\}[[:space:]]*,?[[:space:]]*$ ]]; then
                _stack_store_component_object \
                    "$component_object_key" \
                    "$component_version" \
                    "$component_download_url" \
                    "$component_sha256" \
                    "$line_no"
                in_component_object=0
                component_object_key=""
                component_version=""
                component_download_url=""
                component_sha256=""
            elif [[ "$line" =~ ^[[:space:]]*\"version\"[[:space:]]*:[[:space:]]*\"([^\"]*)\"[[:space:]]*,?[[:space:]]*$ ]]; then
                component_version="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ ^[[:space:]]*\"download_url\"[[:space:]]*:[[:space:]]*\"([^\"]*)\"[[:space:]]*,?[[:space:]]*$ ]]; then
                component_download_url="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ ^[[:space:]]*\"sha256\"[[:space:]]*:[[:space:]]*\"([^\"]*)\"[[:space:]]*,?[[:space:]]*$ ]]; then
                component_sha256="${BASH_REMATCH[1]}"
            else
                fail "Unsupported stack manifest shape at line ${line_no}: ${line}"
            fi
            continue
        fi

        if [[ "$in_components" -eq 1 ]]; then
            if [[ "$line" =~ ^[[:space:]]*\}[[:space:]]*,?[[:space:]]*$ ]]; then
                in_components=0
            elif [[ "$line" =~ ^[[:space:]]*\"([A-Za-z0-9_.:+-]+)\"[[:space:]]*:[[:space:]]*\"([^\"]*)\"[[:space:]]*,?[[:space:]]*$ ]]; then
                key="${BASH_REMATCH[1]}"
                value="${BASH_REMATCH[2]}"
                # shellcheck disable=SC2034
                TT_STACK_COMPONENTS["$key"]="$value"
            elif [[ "$line" =~ ^[[:space:]]*\"([A-Za-z0-9_.:+-]+)\"[[:space:]]*:[[:space:]]*\{[[:space:]]*$ ]]; then
                in_component_object=1
                component_object_key="${BASH_REMATCH[1]}"
                component_version=""
                component_download_url=""
                component_sha256=""
            else
                fail "Unsupported stack manifest shape at line ${line_no}: ${line}"
            fi
            continue
        fi

        if [[ "$line" =~ ^[[:space:]]*\}[[:space:]]*$ ]]; then
            saw_close=1
        elif [[ "$line" =~ ^[[:space:]]*\"release\"[[:space:]]*:[[:space:]]*\"([^\"]*)\"[[:space:]]*,?[[:space:]]*$ ]]; then
            TT_STACK_RELEASE="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^[[:space:]]*\"description\"[[:space:]]*:[[:space:]]*\"([^\"]*)\"[[:space:]]*,?[[:space:]]*$ ]]; then
            TT_STACK_DESCRIPTION="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^[[:space:]]*\"components\"[[:space:]]*:[[:space:]]*\{[[:space:]]*$ ]]; then
            in_components=1
        else
            fail "Unsupported stack manifest shape at line ${line_no}: ${line}"
        fi
    done <"$manifest_file"

    if [[ "$saw_open" -ne 1 || "$saw_close" -ne 1 || "$in_components" -ne 0 || "$in_component_object" -ne 0 ]]; then
        fail "Unsupported stack manifest shape: ${manifest_file}"
    fi
}

parse_stack_manifest() {
    local manifest_file="$1"

    [[ -f "$manifest_file" ]] || fail "Stack manifest file not found: ${manifest_file}"
    _stack_reset_state

    if [[ -z "${TT_MANIFEST_DISABLE_JQ:-}" ]] && command_exists jq; then
        _parse_stack_manifest_with_jq "$manifest_file"
    else
        _parse_stack_manifest_fallback "$manifest_file"
    fi

    validate_stack_manifest
}

# parse_stack_manifest calls this before returning; keep it public for tests and callers
# that build TT_STACK_* values in memory.
validate_stack_manifest() {
    local component

    [[ -n "${TT_STACK_RELEASE:-}" ]] || fail "Missing required stack manifest key: release"

    for component in "${TT_REQUIRED_STACK_COMPONENTS[@]}"; do
        if [[ -z "${TT_STACK_COMPONENTS[$component]:-}" ]]; then
            fail "Missing required stack manifest key: components.${component}"
        fi
    done
}
