#!/usr/bin/env bash
# Local stack manifest capture helpers for tt-env.
#
# Public symbols:
#   - capture_release [--dry-run] [--force] [--base <release>] <release>

if [[ -n "${TT_CAPTURE_LOADED:-}" ]]; then
    return 0
fi
TT_CAPTURE_LOADED=1

CAPTURE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CAPTURE_ROOT="$(cd "${CAPTURE_LIB_DIR}/.." && pwd)"
# shellcheck disable=SC1091
source "${CAPTURE_LIB_DIR}/core.sh"
# shellcheck disable=SC1091
source "${CAPTURE_LIB_DIR}/manifest_parser.sh"
# shellcheck disable=SC1091
source "${CAPTURE_LIB_DIR}/package_manager.sh"

declare -g TT_CAPTURE_BASE_RELEASE=""
# shellcheck disable=SC2034 # copied into before capture mutates stack state
declare -gA TT_CAPTURE_BASE_COMPONENTS=()
# shellcheck disable=SC2034
declare -gA TT_CAPTURE_BASE_SYSTEM_PACKAGES=()
# shellcheck disable=SC2034
declare -gA TT_CAPTURE_BASE_GIT_COMPONENTS_URL=()
# shellcheck disable=SC2034
declare -gA TT_CAPTURE_BASE_GIT_COMPONENTS_ENTRYPOINT=()
# shellcheck disable=SC2034
declare -gA TT_CAPTURE_BASE_CONTAINER_COMPONENTS_IMAGE_URL=()
# shellcheck disable=SC2034
declare -gA TT_CAPTURE_BASE_CONTAINER_COMPONENTS_REF=()
declare -g TT_CAPTURE_CLEANUP_MANIFEST=""

_capture_enable_cleanup() {
    TT_CAPTURE_CLEANUP_MANIFEST="$1"
    trap 'if [[ -n "${TT_CAPTURE_CLEANUP_MANIFEST:-}" ]]; then rm -f -- "$TT_CAPTURE_CLEANUP_MANIFEST"; fi' EXIT
}

_capture_disable_cleanup() {
    TT_CAPTURE_CLEANUP_MANIFEST=""
}

_capture_usage() {
    cat <<'EOF'
Usage:
  tt-env capture [--dry-run] [--force] [--base <release>] <release>
EOF
}

_capture_validate_release_name() {
    local release="$1"

    if [[ ! "$release" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]; then
        fail "Invalid release name: ${release}"
    fi

    case "$release" in
        .|..|*/*|*\\*)
            fail "Invalid release name: ${release}"
            ;;
    esac
}

_capture_stack_manifest_path() {
    local release="$1"
    local tt_home_manifest="${TT_HOME}/releases/${release}.json"
    local bundled_manifest="${CAPTURE_ROOT}/releases/${release}.json"

    _capture_validate_release_name "$release"

    if [[ -f "$tt_home_manifest" ]]; then
        printf '%s\n' "$tt_home_manifest"
    elif [[ -f "$bundled_manifest" ]]; then
        printf '%s\n' "$bundled_manifest"
    else
        fail "Release manifest not found for ${release}."
    fi
}

_capture_os_manifest_path() {
    local os_id="$1"
    local os_version="$2"
    local manifest_name="${os_id}-${os_version}.env"
    local tt_home_manifest="${TT_HOME}/manifests/${manifest_name}"
    local bundled_manifest="${CAPTURE_ROOT}/manifests/${manifest_name}"

    if [[ -f "$tt_home_manifest" ]]; then
        printf '%s\n' "$tt_home_manifest"
    elif [[ -f "$bundled_manifest" ]]; then
        printf '%s\n' "$bundled_manifest"
    else
        fail "OS manifest not found for ${os_id} ${os_version}."
    fi
}

_capture_copy_base_stack() {
    local key

    TT_CAPTURE_BASE_RELEASE="$TT_STACK_RELEASE"
    TT_CAPTURE_BASE_COMPONENTS=()
    TT_CAPTURE_BASE_SYSTEM_PACKAGES=()
    TT_CAPTURE_BASE_GIT_COMPONENTS_URL=()
    TT_CAPTURE_BASE_GIT_COMPONENTS_ENTRYPOINT=()
    TT_CAPTURE_BASE_CONTAINER_COMPONENTS_IMAGE_URL=()
    TT_CAPTURE_BASE_CONTAINER_COMPONENTS_REF=()

    for key in "${!TT_STACK_COMPONENTS[@]}"; do
        TT_CAPTURE_BASE_COMPONENTS["$key"]="${TT_STACK_COMPONENTS[$key]}"
    done
    for key in "${!TT_STACK_SYSTEM_PACKAGES[@]}"; do
        TT_CAPTURE_BASE_SYSTEM_PACKAGES["$key"]="${TT_STACK_SYSTEM_PACKAGES[$key]}"
    done
    for key in "${!TT_STACK_GIT_COMPONENTS_URL[@]}"; do
        TT_CAPTURE_BASE_GIT_COMPONENTS_URL["$key"]="${TT_STACK_GIT_COMPONENTS_URL[$key]}"
        TT_CAPTURE_BASE_GIT_COMPONENTS_ENTRYPOINT["$key"]="${TT_STACK_GIT_COMPONENTS_ENTRYPOINT[$key]:-run.py}"
    done
    for key in "${!TT_STACK_CONTAINER_COMPONENTS_IMAGE_URL[@]}"; do
        TT_CAPTURE_BASE_CONTAINER_COMPONENTS_IMAGE_URL["$key"]="${TT_STACK_CONTAINER_COMPONENTS_IMAGE_URL[$key]}"
    done
    for key in "${!TT_STACK_CONTAINER_COMPONENTS_REF[@]}"; do
        TT_CAPTURE_BASE_CONTAINER_COMPONENTS_REF["$key"]="${TT_STACK_CONTAINER_COMPONENTS_REF[$key]}"
    done
}

_capture_load_base_release() {
    local base_release="$1"
    local manifest_file

    manifest_file="$(_capture_stack_manifest_path "$base_release")"
    parse_stack_manifest "$manifest_file"
    _capture_copy_base_stack
}

_capture_latest_base_release() {
    local target_release="$1"
    local manifest_file
    local release
    local -a entries=()
    local -a manifests=()

    shopt -s nullglob
    manifests=("${CAPTURE_ROOT}/releases/"*.json "${TT_HOME}/releases/"*.json)
    shopt -u nullglob

    for manifest_file in "${manifests[@]}"; do
        if ! release="$(_list_manifest_release_for_capture "$manifest_file" 2>/dev/null)"; then
            continue
        fi
        [[ "$release" != "$target_release" ]] || continue
        if [[ "$release" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2}$ ]]; then
            entries+=("${release}"$'\t'"${manifest_file}")
        fi
    done

    [[ "${#entries[@]}" -gt 0 ]] || fail "No dated base release manifest found for capture."
    printf '%s\n' "${entries[@]}" | sort -t $'\t' -k1,1 | tail -n 1 | cut -f1
}

_list_manifest_release_for_capture() {
    local manifest_file="$1"

    parse_stack_manifest "$manifest_file"
    printf '%s\n' "$TT_STACK_RELEASE"
}

_capture_json_escape() {
    local value="$1"

    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/}"
    printf '%s\n' "$value"
}

_capture_json_pair() {
    local key="$1"
    local value="$2"
    local comma="${3-,}"

    printf '    "%s": "%s"%s\n' "$(_capture_json_escape "$key")" "$(_capture_json_escape "$value")" "$comma"
}

_capture_json_object_start() {
    local key="$1"
    printf '  "%s": {\n' "$(_capture_json_escape "$key")"
}

_capture_command_required() {
    local command_name="$1"
    local purpose="$2"

    command_exists "$command_name" || fail "${command_name} is required to ${purpose}."
}

_capture_apt_latest_version() {
    local package_name="$1"
    local line
    local version=""

    _capture_command_required apt-cache "capture apt package versions"

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" == *"|"* ]] || continue
        version="${line#*|}"
        version="${version%%|*}"
        version="${version#"${version%%[![:space:]]*}"}"
        version="${version%"${version##*[![:space:]]}"}"
        [[ -n "$version" ]] && break
    done < <(apt-cache madison "$package_name")

    [[ -n "$version" ]] || return 1
    printf '%s\n' "$version"
}

_capture_system_packages() {
    local pkg_manager="${TT_MANIFEST_SCALARS[PKG_MANAGER]:-}"
    local virtual_package
    local package_name
    local latest_version

    [[ -n "$pkg_manager" ]] || fail "OS manifest is missing PKG_MANAGER."
    case "$pkg_manager" in
        apt)
            ;;
        *)
            fail "tt-env capture currently supports apt OS manifests only."
            ;;
    esac

    TT_STACK_SYSTEM_PACKAGES=()
    for virtual_package in "${TT_PACKAGE_MANAGER_PINNED_VIRTUAL_PACKAGES[@]}" "${TT_PACKAGE_MANAGER_OPTIONAL_VIRTUAL_PACKAGES[@]}"; do
        if ! package_name="$(resolve_package "$virtual_package" 2>/dev/null)"; then
            if _package_manager_virtual_package_is_optional "$virtual_package"; then
                continue
            fi
            fail "Failed to resolve package from OS manifest: ${virtual_package}"
        fi
        if latest_version="$(_capture_apt_latest_version "$package_name")"; then
            TT_STACK_SYSTEM_PACKAGES["$virtual_package"]="$latest_version"
        elif _package_manager_virtual_package_is_optional "$virtual_package"; then
            log_warn "Could not capture optional system package ${virtual_package}; keeping base value if present."
            if [[ -n "${TT_CAPTURE_BASE_SYSTEM_PACKAGES[$virtual_package]:-}" ]]; then
                TT_STACK_SYSTEM_PACKAGES["$virtual_package"]="${TT_CAPTURE_BASE_SYSTEM_PACKAGES[$virtual_package]}"
            fi
        else
            fail "Could not determine latest apt version for ${package_name}."
        fi
    done
}

_capture_pypi_latest_version() {
    local package_name="$1"
    local url="https://pypi.org/pypi/${package_name}/json"
    local payload
    local version

    _capture_command_required curl "fetch PyPI package metadata"
    _capture_command_required python3 "parse PyPI package metadata"

    payload="$(curl --fail --location --silent --show-error "$url")" || \
        fail "Failed to fetch PyPI metadata for ${package_name}."
    version="$(python3 -c 'import json, sys; print(json.load(sys.stdin)["info"]["version"])' <<<"$payload")" || \
        fail "Failed to parse PyPI metadata for ${package_name}."
    [[ "$version" =~ ^[A-Za-z0-9][A-Za-z0-9_.!+-]*$ ]] || \
        fail "Invalid PyPI version for ${package_name}: ${version}"
    printf '%s\n' "$version"
}

_capture_python_packages() {
    local package_name

    TT_STACK_PYTHON_PACKAGES=()
    for package_name in "${TT_PACKAGE_MANAGER_PIP_PACKAGES[@]}"; do
        TT_STACK_PYTHON_PACKAGES["$package_name"]="$(_capture_pypi_latest_version "$package_name")"
    done
}

_capture_git_head() {
    local url="$1"
    local line
    local revision=""

    _capture_command_required git "capture git component revisions"

    while IFS= read -r line || [[ -n "$line" ]]; do
        case "$line" in
            ref:*)
                continue
                ;;
            *$'\t'HEAD)
                revision="${line%%$'\t'*}"
                break
                ;;
        esac
    done < <(git ls-remote --symref "$url" HEAD)

    [[ "$revision" =~ ^[A-Fa-f0-9]{40}$ ]] || fail "Could not determine git HEAD for ${url}."
    printf '%s\n' "$revision"
}

_capture_git_components() {
    local component
    local -a components=()

    TT_STACK_GIT_COMPONENTS_URL=()
    TT_STACK_GIT_COMPONENTS_VERSION=()
    TT_STACK_GIT_COMPONENTS_ENTRYPOINT=()

    mapfile -t components < <(printf '%s\n' "${!TT_CAPTURE_BASE_GIT_COMPONENTS_URL[@]}" | sed '/^$/d' | sort)
    for component in "${components[@]}"; do
        TT_STACK_GIT_COMPONENTS_URL["$component"]="${TT_CAPTURE_BASE_GIT_COMPONENTS_URL[$component]}"
        TT_STACK_GIT_COMPONENTS_VERSION["$component"]="$(_capture_git_head "${TT_CAPTURE_BASE_GIT_COMPONENTS_URL[$component]}")"
        TT_STACK_GIT_COMPONENTS_ENTRYPOINT["$component"]="${TT_CAPTURE_BASE_GIT_COMPONENTS_ENTRYPOINT[$component]:-run.py}"
    done
}

_capture_tt_metal_latest_tag() {
    local repo="${TT_CAPTURE_TT_METAL_REPO:-https://github.com/tenstorrent/tt-metal.git}"
    local tag

    _capture_command_required git "capture tt-metal tags"

    tag="$(
        git ls-remote --tags --refs "$repo" |
            awk '{print $2}' |
            sed 's#refs/tags/##' |
            grep -E '^v[0-9]+\.[0-9]+\.[0-9]+(-(dev[0-9]{8}|rc[0-9]+))?$' |
            sort -V |
            tail -n 1
    )"

    [[ -n "$tag" ]] || fail "Could not determine latest tt-metal tag from ${repo}."
    printf '%s\n' "$tag"
}

_capture_components() {
    local key

    TT_STACK_COMPONENTS=()
    for key in "${!TT_CAPTURE_BASE_COMPONENTS[@]}"; do
        TT_STACK_COMPONENTS["$key"]="${TT_CAPTURE_BASE_COMPONENTS[$key]}"
    done

    if [[ -n "${TT_STACK_SYSTEM_PACKAGES[kmd]:-}" ]]; then
        TT_STACK_COMPONENTS["tt-kmd"]="ttkmd-${TT_STACK_SYSTEM_PACKAGES[kmd]}"
    fi
    if [[ -n "${TT_STACK_PYTHON_PACKAGES[tt-smi]:-}" ]]; then
        TT_STACK_COMPONENTS["tt-smi"]="v${TT_STACK_PYTHON_PACKAGES[tt-smi]}"
    fi
    TT_STACK_COMPONENTS["tt-metal"]="$(_capture_tt_metal_latest_tag)"
    if [[ -n "${TT_CAPTURE_BASE_COMPONENTS[firmware]:-}" ]]; then
        TT_STACK_COMPONENTS["firmware"]="${TT_CAPTURE_BASE_COMPONENTS[firmware]}"
        log_warn "Keeping firmware component from base release: ${TT_STACK_COMPONENTS[firmware]}"
    fi
}

_capture_ghcr_latest_digest() {
    local image_url="$1"
    local repo="${image_url#ghcr.io/}"
    local token_url
    local token_payload
    local token
    local headers_file
    local digest

    [[ "$image_url" == ghcr.io/* ]] || fail "Unsupported container registry for capture: ${image_url}"
    _capture_command_required curl "fetch container image metadata"
    _capture_command_required python3 "parse container registry metadata"

    token_url="https://ghcr.io/token?service=ghcr.io&scope=repository:${repo}:pull"
    token_payload="$(curl --fail --location --silent --show-error "$token_url")" || \
        fail "Failed to fetch GHCR token for ${image_url}."
    token="$(python3 -c 'import json, sys; print(json.load(sys.stdin)["token"])' <<<"$token_payload")" || \
        fail "Failed to parse GHCR token for ${image_url}."
    [[ -n "$token" ]] || fail "GHCR token response did not include a token for ${image_url}."

    headers_file="$(mktemp)" || fail "Failed to create temporary header file."
    curl \
        --fail \
        --location \
        --silent \
        --show-error \
        --head \
        --dump-header "$headers_file" \
        --output /dev/null \
        --header "Authorization: Bearer ${token}" \
        --header "Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json" \
        "https://ghcr.io/v2/${repo}/manifests/latest" || {
            rm -f -- "$headers_file"
            fail "Failed to fetch GHCR manifest digest for ${image_url}."
        }

    digest="$(awk 'tolower($1) == "docker-content-digest:" {print $2; exit}' "$headers_file")"
    rm -f -- "$headers_file"
    digest="${digest%$'\r'}"
    [[ "$digest" =~ ^sha256:[A-Fa-f0-9]{64}$ ]] || fail "GHCR manifest digest not found for ${image_url}."
    printf '%s\n' "$digest"
}

_capture_container_components() {
    local component
    local image_url
    local -a components=()

    TT_STACK_CONTAINER_COMPONENTS_IMAGE_URL=()
    TT_STACK_CONTAINER_COMPONENTS_IMAGE_TAG=()
    TT_STACK_CONTAINER_COMPONENTS_REF=()

    for component in "${!TT_CAPTURE_BASE_CONTAINER_COMPONENTS_REF[@]}"; do
        TT_STACK_CONTAINER_COMPONENTS_REF["$component"]="${TT_CAPTURE_BASE_CONTAINER_COMPONENTS_REF[$component]}"
    done

    mapfile -t components < <(printf '%s\n' "${!TT_CAPTURE_BASE_CONTAINER_COMPONENTS_IMAGE_URL[@]}" | sed '/^$/d' | sort)
    for component in "${components[@]}"; do
        if [[ -n "${TT_CAPTURE_BASE_CONTAINER_COMPONENTS_REF[$component]:-}" ]]; then
            continue
        fi
        image_url="${TT_CAPTURE_BASE_CONTAINER_COMPONENTS_IMAGE_URL[$component]}"
        TT_STACK_CONTAINER_COMPONENTS_IMAGE_URL["$component"]="$image_url"
        TT_STACK_CONTAINER_COMPONENTS_IMAGE_TAG["$component"]="$(_capture_ghcr_latest_digest "$image_url")"
    done
}

_capture_write_manifest() {
    local output_file="$1"
    local release="$2"
    local component
    local package_key
    local package_name
    local comma
    local i
    local last_index
    local -a keys=()

    {
        printf '{\n'
        printf '  "release": "%s",\n' "$(_capture_json_escape "$release")"
        printf '  "description": "Local-only Tenstorrent stack snapshot %s, captured from %s",\n' \
            "$(_capture_json_escape "$release")" \
            "$(_capture_json_escape "$TT_CAPTURE_BASE_RELEASE")"

        _capture_json_object_start "components"
        mapfile -t keys < <(
            for component in "tt-kmd" "tt-smi" "firmware" "tt-metal"; do
                [[ -n "${TT_STACK_COMPONENTS[$component]:-}" ]] && printf '%s\n' "$component"
            done
        )
        last_index=$((${#keys[@]} - 1))
        for i in "${!keys[@]}"; do
            component="${keys[$i]}"
            comma=","
            [[ "$i" -eq "$last_index" ]] && comma=""
            _capture_json_pair "$component" "${TT_STACK_COMPONENTS[$component]}" "$comma"
        done
        printf '  },\n'

        _capture_json_object_start "system_packages"
        mapfile -t keys < <(printf '%s\n' "${!TT_STACK_SYSTEM_PACKAGES[@]}" | sed '/^$/d' | sort)
        last_index=$((${#keys[@]} - 1))
        for i in "${!keys[@]}"; do
            package_key="${keys[$i]}"
            comma=","
            [[ "$i" -eq "$last_index" ]] && comma=""
            _capture_json_pair "$package_key" "${TT_STACK_SYSTEM_PACKAGES[$package_key]}" "$comma"
        done
        printf '  },\n'

        _capture_json_object_start "python_packages"
        last_index=$((${#TT_PACKAGE_MANAGER_PIP_PACKAGES[@]} - 1))
        for i in "${!TT_PACKAGE_MANAGER_PIP_PACKAGES[@]}"; do
            package_name="${TT_PACKAGE_MANAGER_PIP_PACKAGES[$i]}"
            comma=","
            [[ "$i" -eq "$last_index" ]] && comma=""
            _capture_json_pair "$package_name" "${TT_STACK_PYTHON_PACKAGES[$package_name]}" "$comma"
        done
        printf '  },\n'

        _capture_json_object_start "git_components"
        mapfile -t keys < <(printf '%s\n' "${!TT_STACK_GIT_COMPONENTS_URL[@]}" | sed '/^$/d' | sort)
        last_index=$((${#keys[@]} - 1))
        for i in "${!keys[@]}"; do
            component="${keys[$i]}"
            comma=","
            [[ "$i" -eq "$last_index" ]] && comma=""
            printf '    "%s": {\n' "$(_capture_json_escape "$component")"
            printf '      "url": "%s",\n' "$(_capture_json_escape "${TT_STACK_GIT_COMPONENTS_URL[$component]}")"
            printf '      "version": "%s"' "$(_capture_json_escape "${TT_STACK_GIT_COMPONENTS_VERSION[$component]}")"
            if [[ "${TT_STACK_GIT_COMPONENTS_ENTRYPOINT[$component]:-run.py}" != "run.py" ]]; then
                printf ',\n      "entrypoint": "%s"\n' "$(_capture_json_escape "${TT_STACK_GIT_COMPONENTS_ENTRYPOINT[$component]}")"
                printf '    }%s\n' "$comma"
            else
                printf '\n    }%s\n' "$comma"
            fi
        done
        printf '  },\n'

        _capture_json_object_start "container_components"
        mapfile -t keys < <(
            {
                printf '%s\n' "${!TT_STACK_CONTAINER_COMPONENTS_REF[@]}"
                printf '%s\n' "${!TT_STACK_CONTAINER_COMPONENTS_IMAGE_URL[@]}"
            } | sed '/^$/d' | sort -u
        )
        last_index=$((${#keys[@]} - 1))
        for i in "${!keys[@]}"; do
            component="${keys[$i]}"
            comma=","
            [[ "$i" -eq "$last_index" ]] && comma=""
            printf '    "%s": {\n' "$(_capture_json_escape "$component")"
            if [[ -n "${TT_STACK_CONTAINER_COMPONENTS_REF[$component]:-}" ]]; then
                printf '      "ref": "%s"\n' "$(_capture_json_escape "${TT_STACK_CONTAINER_COMPONENTS_REF[$component]}")"
            else
                printf '      "image_url": "%s",\n' "$(_capture_json_escape "${TT_STACK_CONTAINER_COMPONENTS_IMAGE_URL[$component]}")"
                printf '      "image_tag": "%s"\n' "$(_capture_json_escape "${TT_STACK_CONTAINER_COMPONENTS_IMAGE_TAG[$component]}")"
            fi
            printf '    }%s\n' "$comma"
        done
        printf '  }\n'
        printf '}\n'
    } >"$output_file" || fail "Failed to write captured manifest: ${output_file}"
}

_capture_validate_manifest_file() {
    local manifest_file="$1"

    parse_stack_manifest "$manifest_file"
    validate_stack_manifest
}

capture_release() {
    local arg
    local release=""
    local base_release=""
    local base_manifest
    local target_manifest
    local dry_run=0
    local force=0
    local detected_os_id
    local detected_os_version
    local os_manifest
    local tmp_root
    local tmp_manifest

    while [[ "$#" -gt 0 ]]; do
        arg="$1"
        case "$arg" in
            --dry-run)
                dry_run=1
                ;;
            --force)
                force=1
                ;;
            --base)
                shift || fail "--base requires a release argument."
                base_release="${1:-}"
                [[ -n "$base_release" ]] || fail "--base requires a release argument."
                _capture_validate_release_name "$base_release"
                ;;
            --help|-h)
                _capture_usage
                return 0
                ;;
            -*)
                fail "Unknown capture option: ${arg}"
                ;;
            *)
                [[ -z "$release" ]] || fail "capture accepts exactly one release argument."
                release="$arg"
                _capture_validate_release_name "$release"
                ;;
        esac
        shift
    done

    if [[ -z "$release" ]]; then
        _capture_usage
        return 1
    fi

    target_manifest="${TT_HOME}/releases/${release}.json"
    if [[ "$dry_run" -eq 0 && "$force" -eq 0 && -e "$target_manifest" ]]; then
        fail "Release manifest already exists: ${target_manifest}. Use --force to overwrite."
    fi

    detect_os
    detected_os_id="${OS_ID:-}"
    detected_os_version="${OS_VERSION:-}"
    [[ -n "$detected_os_id" && -n "$detected_os_version" ]] || fail "OS detection did not set OS_ID and OS_VERSION."
    os_manifest="$(_capture_os_manifest_path "$detected_os_id" "$detected_os_version")"
    parse_env_manifest "$os_manifest"

    if [[ -z "$base_release" ]]; then
        base_release="$(_capture_latest_base_release "$release")"
    fi
    base_manifest="$(_capture_stack_manifest_path "$base_release")"
    parse_stack_manifest "$base_manifest"
    _capture_copy_base_stack

    TT_STACK_RELEASE="$release"
    _capture_system_packages
    _capture_python_packages
    _capture_git_components
    _capture_components
    _capture_container_components

    tmp_root="${TT_HOME}/.tmp"
    mkdir -p "$tmp_root" || fail "Failed to create capture temp directory: ${tmp_root}"
    tmp_manifest="$(mktemp "${tmp_root}/capture.${release}.XXXXXX.json")" || \
        fail "Failed to create capture temp manifest."
    _capture_enable_cleanup "$tmp_manifest"
    _capture_write_manifest "$tmp_manifest" "$release"
    _capture_validate_manifest_file "$tmp_manifest"

    if [[ "$dry_run" -eq 1 ]]; then
        cat "$tmp_manifest"
        rm -f -- "$tmp_manifest"
        _capture_disable_cleanup
        return 0
    fi

    mkdir -p "${TT_HOME}/releases" || fail "Failed to create release manifest directory: ${TT_HOME}/releases"
    mv -f -- "$tmp_manifest" "$target_manifest" || fail "Failed to write release manifest: ${target_manifest}"
    _capture_disable_cleanup
    log_info "Captured local release manifest: ${target_manifest}"
}
