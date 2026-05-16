#!/usr/bin/env bash
# Manifest listing and update helpers for tt-env.
#
# Public symbols:
#   - list_releases
#   - maybe_update_manifests
#   - update_self
#   - update_manifests

if [[ -n "${TT_UPDATER_LOADED:-}" ]]; then
    return 0
fi
TT_UPDATER_LOADED=1

UPDATER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPDATER_ROOT="$(cd "${UPDATER_LIB_DIR}/.." && pwd)"
# shellcheck disable=SC1091
source "${UPDATER_LIB_DIR}/core.sh"
# shellcheck disable=SC1091
source "${UPDATER_LIB_DIR}/security.sh"
# shellcheck disable=SC1091
source "${UPDATER_LIB_DIR}/manifest_parser.sh"

declare -g TT_UPDATE_CLEANUP_DIR=""
declare -g TT_UPDATE_SOURCE_USED=""
export TT_SELF_UPDATE_PROCEED=0
export TT_SELF_UPDATE_REMOTE_VERSION=""

_list_usage() {
    cat <<'EOF'
Usage:
  tt-env list
EOF
}

_update_usage() {
    cat <<'EOF'
Usage:
  tt-env update
  tt-env update --self
EOF
}

_update_self_usage() {
    cat <<'EOF'
Usage:
  tt-env update --self
EOF
}

_list_release_installed() {
    local release="$1"
    local version_dir="${TT_HOME}/versions/${release}"

    [[ -d "$version_dir" && -f "${version_dir}/.tt-env-installed" ]]
}

_list_manifest_release() {
    local manifest_file="$1"

    parse_stack_manifest "$manifest_file"
    printf '%s\n' "$TT_STACK_RELEASE"
}

list_releases() {
    local arg
    local manifest_file
    local release
    local state
    local -a manifests=()

    while [[ "$#" -gt 0 ]]; do
        arg="$1"
        case "$arg" in
            --help|-h)
                _list_usage
                return 0
                ;;
            *)
                fail "Unknown list option: ${arg}"
                ;;
        esac
        shift
    done

    shopt -s nullglob
    manifests=("${TT_HOME}/releases/"*.json)
    shopt -u nullglob

    printf 'Releases\n'
    if [[ "${#manifests[@]}" -eq 0 ]]; then
        printf '  (none)\n'
        return 0
    fi

    for manifest_file in "${manifests[@]}"; do
        if ! release="$(_list_manifest_release "$manifest_file" 2>/dev/null)"; then
            log_warn "Skipping invalid release manifest: ${manifest_file}"
            continue
        fi

        if _list_release_installed "$release"; then
            state="installed"
        else
            state="available"
        fi

        printf '  %s [%s]\n' "$release" "$state"
    done
}

_update_validate_source() {
    local repo="$1"
    local ref="$2"

    if [[ ! "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
        fail "Invalid manifests repository: ${repo}"
    fi

    if [[ ! "$ref" =~ ^[A-Za-z0-9_./-]+$ ]]; then
        fail "Invalid manifests ref: ${ref}"
    fi
}

_update_config_file() {
    printf '%s\n' "${TT_UPDATE_CONFIG_FILE:-${TT_HOME}/config}"
}

_update_configured_mirrors() {
    local config_file

    config_file="$(_update_config_file)"
    [[ -f "$config_file" ]] || return 0

    parse_env_manifest "$config_file"
    if declare -p TT_MANIFEST_LIST_MIRRORS >/dev/null 2>&1; then
        printf '%s\n' "${TT_MANIFEST_LIST_MIRRORS[@]}"
    fi
}

_update_source_repos() {
    local repo="$1"
    local mirror
    local -a sources=()

    while IFS= read -r mirror; do
        [[ -n "$mirror" ]] || continue
        sources+=("$mirror")
    done < <(_update_configured_mirrors)
    sources+=("$repo")

    printf '%s\n' "${sources[@]}"
}

_update_auth_token() {
    local token

    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        printf '%s\n' "$GITHUB_TOKEN"
        return 0
    fi

    if [[ -n "${GH_TOKEN:-}" ]]; then
        printf '%s\n' "$GH_TOKEN"
        return 0
    fi

    if command_exists gh; then
        token="$(gh auth token 2>/dev/null)" || token=""
        if [[ -n "$token" ]]; then
            printf '%s\n' "$token"
            return 0
        fi
    fi

    return 1
}

_update_enable_cleanup() {
    TT_UPDATE_CLEANUP_DIR="$1"
    trap 'if [[ -n "${TT_UPDATE_CLEANUP_DIR:-}" ]]; then rm -rf -- "$TT_UPDATE_CLEANUP_DIR"; fi' EXIT
}

_update_disable_cleanup() {
    TT_UPDATE_CLEANUP_DIR=""
}

_update_require_tools() {
    command_exists curl || fail "curl is required to update manifests."
    command_exists tar || fail "tar is required to update manifests."
    command_exists mktemp || fail "mktemp is required to update manifests."
    command_exists gpg || fail "gpg is required to verify updated manifests."
}

_update_last_update_file() {
    printf '%s\n' "${TT_UPDATE_LAST_UPDATE_FILE:-${TT_STATUS_LAST_UPDATE_FILE:-${TT_HOME}/manifests/last_update}}"
}

_update_now_epoch() {
    local now_epoch="${TT_UPDATE_NOW_EPOCH:-}"

    if [[ -z "$now_epoch" ]]; then
        now_epoch="$(date +%s)" || fail "Failed to read current time."
    fi

    [[ "$now_epoch" =~ ^[0-9]+$ ]] || fail "Invalid update timestamp: ${now_epoch}"
    printf '%s\n' "$now_epoch"
}

_update_mark_success() {
    local marker
    local marker_dir
    local now_epoch

    marker="$(_update_last_update_file)"
    marker_dir="$(dirname "$marker")"
    now_epoch="$(_update_now_epoch)"

    mkdir -p "$marker_dir" || fail "Failed to create update marker directory: ${marker_dir}"
    printf '%s\n' "$now_epoch" >"$marker" || \
        fail "Failed to write update marker: ${marker}"
}

_update_cache_is_fresh() {
    local marker
    local updated_epoch=""
    local now_epoch
    local delta
    local ttl="${TT_UPDATE_CACHE_SECONDS:-10800}"

    [[ "$ttl" =~ ^[0-9]+$ ]] || fail "Invalid update cache TTL: ${ttl}"

    marker="$(_update_last_update_file)"
    [[ -f "$marker" ]] || return 1

    updated_epoch="$(<"$marker")" || updated_epoch=""
    updated_epoch="${updated_epoch//$'\r'/}"
    updated_epoch="${updated_epoch//$'\n'/}"
    [[ "$updated_epoch" =~ ^[0-9]+$ ]] || return 1

    now_epoch="$(_update_now_epoch)"
    delta=$((now_epoch - updated_epoch))
    [[ "$delta" -lt 0 ]] && delta=0

    [[ "$delta" -lt "$ttl" ]]
}

_update_write_headers() {
    local headers_file="$1"
    local token="$2"
    local old_umask

    old_umask="$(umask)"
    umask 077
    {
        printf 'Authorization: Bearer %s\n' "$token"
        printf 'Accept: application/vnd.github+json\n'
    } >"$headers_file" || {
        umask "$old_umask"
        fail "Failed to create update authentication headers."
    }
    umask "$old_umask"
}

_update_fetch_archive() {
    local archive_file="$1"
    local headers_file="$2"
    local ref="$3"
    shift 3
    local repo
    local url
    local http_code
    local last_error="No manifest sources configured."

    TT_UPDATE_SOURCE_USED=""

    for repo in "$@"; do
        if ! ( _update_validate_source "$repo" "$ref" ) >/dev/null 2>&1; then
            last_error="Invalid manifest source: ${repo}"
            log_warn "$last_error"
            continue
        fi
        url="https://api.github.com/repos/${repo}/tarball/${ref}"

        if ! http_code="$(curl \
            --location \
            --retry 3 \
            --silent \
            --show-error \
            --output "$archive_file" \
            --write-out "%{http_code}" \
            --header "@${headers_file}" \
            "$url")"; then
            last_error="Failed to fetch manifests from ${url}."
            log_warn "$last_error"
            continue
        fi

        if [[ "$http_code" == "200" ]]; then
            TT_UPDATE_SOURCE_USED="$repo"
            return 0
        fi

        if [[ "$http_code" == "401" || "$http_code" == "403" ]]; then
            last_error="Authentication failed while fetching manifests from ${repo}. Check GITHUB_TOKEN or run: gh auth login"
        else
            last_error="Failed to fetch manifests from ${url} (HTTP ${http_code})."
        fi
        log_warn "$last_error"
    done

    fail "Failed to fetch manifests from all configured sources. ${last_error}"
}

_self_update_trim_version() {
    local version="$1"

    version="${version//$'\r'/}"
    version="${version//$'\n'/}"
    version="${version#"${version%%[![:space:]]*}"}"
    version="${version%"${version##*[![:space:]]}"}"
    printf '%s\n' "$version"
}

_self_update_validate_semver() {
    local label="$1"
    local version

    version="$(_self_update_trim_version "$2")"
    [[ "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || \
        fail "Invalid semver in ${label}: ${version:-<empty>}"
    printf '%s\n' "$version"
}

_self_update_semver_compare() {
    local left
    local right
    local i
    local -a left_parts=()
    local -a right_parts=()

    if ! left="$(_self_update_validate_semver "local VERSION" "$1")"; then
        return 1
    fi
    if ! right="$(_self_update_validate_semver "remote VERSION" "$2")"; then
        return 1
    fi
    IFS=. read -r -a left_parts <<<"$left"
    IFS=. read -r -a right_parts <<<"$right"

    for i in 0 1 2; do
        if (( 10#${left_parts[$i]} < 10#${right_parts[$i]} )); then
            printf '%s\n' "-1"
            return 0
        fi
        if (( 10#${left_parts[$i]} > 10#${right_parts[$i]} )); then
            printf '%s\n' "1"
            return 0
        fi
    done

    printf '%s\n' "0"
}

_self_update_local_version_file() {
    printf '%s\n' "${TT_SELF_UPDATE_LOCAL_VERSION_FILE:-${UPDATER_ROOT}/VERSION}"
}

_self_update_read_local_version() {
    local version_file
    local version

    if ! version_file="$(_self_update_local_version_file)"; then
        return 1
    fi
    [[ -f "$version_file" ]] || fail "VERSION file not found at ${version_file}"
    version="$(<"$version_file")"
    _self_update_validate_semver "local VERSION" "$version"
}

_self_update_remote_version_url() {
    local repo="${TT_SELF_UPDATE_REPO:-tetsuh/tt-env-proto1}"
    local ref="${TT_SELF_UPDATE_REF:-main}"
    local version_url

    if [[ -n "${TT_SELF_UPDATE_VERSION_URL:-}" ]]; then
        version_url="$TT_SELF_UPDATE_VERSION_URL"
        [[ "$version_url" == https://* ]] || fail "Invalid self-update VERSION URL: ${version_url}"
        printf '%s\n' "$version_url"
        return 0
    fi

    _update_validate_source "$repo" "$ref"
    version_url="https://api.github.com/repos/${repo}/contents/VERSION?ref=${ref}"
    printf '%s\n' "$version_url"
}

_self_update_validate_https_url() {
    local label="$1"
    local url="$2"

    [[ "$url" == https://* ]] || fail "Invalid ${label} URL: ${url}"
    printf '%s\n' "$url"
}

_self_update_content_url() {
    local path="$1"
    local repo="${TT_SELF_UPDATE_REPO:-tetsuh/tt-env-proto1}"
    local ref="${TT_SELF_UPDATE_REF:-main}"

    _update_validate_source "$repo" "$ref"
    printf 'https://api.github.com/repos/%s/contents/%s?ref=%s\n' "$repo" "$path" "$ref"
}

_self_update_binary_url() {
    local binary_url

    if [[ -n "${TT_SELF_UPDATE_BINARY_URL:-}" ]]; then
        _self_update_validate_https_url "self-update binary" "$TT_SELF_UPDATE_BINARY_URL"
        return 0
    fi

    _self_update_content_url "bin/tt-env"
}

_self_update_target_file() {
    printf '%s\n' "${TT_SELF_UPDATE_TARGET_FILE:-${UPDATER_ROOT}/bin/tt-env}"
}

_self_update_fetch_url() {
    local url="$1"
    local output_file="$2"
    local label="$3"
    local http_code
    local token=""
    local -a curl_args=()

    command_exists curl || fail "curl is required to ${label}."

    curl_args=(
        --location \
        --silent \
        --show-error \
        --output "$output_file" \
        --write-out "%{http_code}"
    )

    if [[ "$url" == https://api.github.com/* ]]; then
        curl_args+=(--header "Accept: application/vnd.github.raw")
        if token="$(_update_auth_token)"; then
            curl_args+=(--header "Authorization: Bearer ${token}")
        fi
    fi
    curl_args+=("$url")

    if ! http_code="$(curl "${curl_args[@]}")"; then
        fail "Failed to ${label} from ${url}."
    fi

    if [[ "$http_code" != "200" ]]; then
        fail "Failed to ${label} from ${url} (HTTP ${http_code})."
    fi
}

_self_update_fetch_remote_version() {
    local version_url="$1"
    local tmp_dir
    local work_dir
    local version_file
    local version

    command_exists mktemp || fail "mktemp is required to check for self-updates."

    tmp_dir="${TT_HOME}/.tmp"
    mkdir -p "$tmp_dir" || fail "Failed to create self-update temp directory: ${tmp_dir}"
    work_dir="$(mktemp -d "${tmp_dir}/self-update.XXXXXX")" || \
        fail "Failed to create self-update temp directory."
    _update_enable_cleanup "$work_dir"
    version_file="${work_dir}/VERSION"

    _self_update_fetch_url "$version_url" "$version_file" "fetch remote VERSION"
    version="$(<"$version_file")"
    rm -rf -- "$work_dir"
    _update_disable_cleanup
    _self_update_validate_semver "remote VERSION" "$version"
}

_self_update_apply_update() {
    local target_file
    local target_dir
    local work_dir
    local binary_tmp
    local binary_url

    command_exists mktemp || fail "mktemp is required to apply self-updates."
    command_exists chmod || fail "chmod is required to apply self-updates."
    command_exists mv || fail "mv is required to apply self-updates."

    if ! target_file="$(_self_update_target_file)"; then
        return 1
    fi
    [[ -f "$target_file" ]] || fail "Self-update target not found: ${target_file}"

    target_dir="$(dirname "$target_file")"
    [[ -d "$target_dir" ]] || fail "Self-update target directory not found: ${target_dir}"

    if ! binary_url="$(_self_update_binary_url)"; then
        return 1
    fi

    # Stage under the target directory so the final rename stays atomic.
    work_dir="$(mktemp -d "${target_dir}/.tt-env-self-update.XXXXXX")" || \
        fail "Failed to create self-update staging directory."
    _update_enable_cleanup "$work_dir"
    binary_tmp="${work_dir}/tt-env.tmp"

    _self_update_fetch_url "$binary_url" "$binary_tmp" "download self-update binary"

    chmod +x "$binary_tmp" || fail "Failed to mark self-update binary executable."
    mv -f -- "$binary_tmp" "$target_file" || fail "Failed to replace tt-env binary atomically."

    rm -rf -- "$work_dir"
    _update_disable_cleanup
}

update_self() {
    local arg
    local local_version
    local remote_version
    local comparison
    local version_url

    export TT_SELF_UPDATE_PROCEED=0
    export TT_SELF_UPDATE_REMOTE_VERSION=""

    while [[ "$#" -gt 0 ]]; do
        arg="$1"
        case "$arg" in
            --self)
                ;;
            --help|-h)
                _update_self_usage
                return 0
                ;;
            *)
                fail "Unknown self-update option: ${arg}"
                ;;
        esac
        shift
    done

    # These checks keep failures visible when callers source this library
    # without set -e; fail may run inside command substitutions.
    if ! local_version="$(_self_update_read_local_version)"; then
        return 1
    fi
    if ! version_url="$(_self_update_remote_version_url)"; then
        return 1
    fi
    if ! remote_version="$(_self_update_fetch_remote_version "$version_url")"; then
        return 1
    fi
    export TT_SELF_UPDATE_REMOTE_VERSION="$remote_version"

    if ! comparison="$(_self_update_semver_compare "$local_version" "$remote_version")"; then
        return 1
    fi
    case "$comparison" in
        -1)
            export TT_SELF_UPDATE_PROCEED=1
            log_info "Self-update available: ${local_version} -> ${remote_version}."
            if _self_update_apply_update; then
                log_info "Updated tt-env to ${remote_version}."
            fi
            ;;
        0)
            log_info "tt-env is already up to date (${local_version})."
            ;;
        1)
            log_info "Local tt-env (${local_version}) is newer than remote (${remote_version}); skipping self-update."
            ;;
    esac
}

_update_stage_manifests() {
    local archive_file="$1"
    local extract_dir="$2"
    local staging_dir="$3"
    local -a release_files=()
    local -a os_manifest_files=()

    mkdir -p "$extract_dir" "$staging_dir" || fail "Failed to create update staging directories."

    tar -xzf "$archive_file" -C "$extract_dir" --strip-components=1 || \
        fail "Failed to extract manifest archive."

    [[ -d "${extract_dir}/releases" ]] || fail "Manifest archive is missing releases/."
    [[ -d "${extract_dir}/manifests" ]] || fail "Manifest archive is missing manifests/."
    _update_verify_manifest_tree "$extract_dir"

    mkdir -p "${staging_dir}/releases" "${staging_dir}/manifests" || \
        fail "Failed to create manifest staging directories."

    shopt -s nullglob
    release_files=("${extract_dir}/releases/"*.json)
    os_manifest_files=("${extract_dir}/manifests/"*.env)
    shopt -u nullglob

    cp -- "${release_files[@]}" "${staging_dir}/releases/" || \
        fail "Failed to stage release manifests."
    cp -- "${os_manifest_files[@]}" "${staging_dir}/manifests/" || \
        fail "Failed to stage OS manifests."
}

_update_verify_manifest_tree() {
    local extract_dir="$1"
    local -a release_files=()
    local -a os_manifest_files=()

    shopt -s nullglob
    release_files=("${extract_dir}/releases/"*.json)
    os_manifest_files=("${extract_dir}/manifests/"*.env)
    shopt -u nullglob

    [[ "${#release_files[@]}" -gt 0 ]] || fail "Manifest archive does not contain release manifests."
    [[ "${#os_manifest_files[@]}" -gt 0 ]] || fail "Manifest archive does not contain OS manifests."
}

_update_restore_backup_dir() {
    local backup_dir="$1"
    local target_dir="$2"

    if [[ -e "$backup_dir" ]]; then
        rm -rf -- "$target_dir"
        mv -- "$backup_dir" "$target_dir" || true
    fi
}

_update_apply_staged_manifests() {
    local staging_dir="$1"
    local backup_dir="$2"
    local releases_backup="${backup_dir}/releases"
    local manifests_backup="${backup_dir}/manifests"

    mkdir -p "$backup_dir" || fail "Failed to create update backup directory."

    if [[ -e "${TT_HOME}/releases" ]]; then
        mv -- "${TT_HOME}/releases" "$releases_backup" || \
            fail "Failed to stage existing release manifests for replacement."
    fi

    if [[ -e "${TT_HOME}/manifests" ]]; then
        mv -- "${TT_HOME}/manifests" "$manifests_backup" || {
            _update_restore_backup_dir "$releases_backup" "${TT_HOME}/releases"
            fail "Failed to stage existing OS manifests for replacement."
        }
    fi

    if ! mv -- "${staging_dir}/releases" "${TT_HOME}/releases"; then
        _update_restore_backup_dir "$releases_backup" "${TT_HOME}/releases"
        _update_restore_backup_dir "$manifests_backup" "${TT_HOME}/manifests"
        fail "Failed to replace release manifests."
    fi

    if ! mv -- "${staging_dir}/manifests" "${TT_HOME}/manifests"; then
        rm -rf -- "${TT_HOME}/releases"
        _update_restore_backup_dir "$releases_backup" "${TT_HOME}/releases"
        _update_restore_backup_dir "$manifests_backup" "${TT_HOME}/manifests"
        fail "Failed to replace OS manifests."
    fi

    rm -rf -- "$backup_dir"
}

# shellcheck disable=SC2120 # Called with CLI arguments from bin/tt-env.
update_manifests() {
    local arg
    local repo="${TT_UPDATE_MANIFESTS_REPO:-tetsuh/tt-env-manifests-proto1}"
    local ref="${TT_UPDATE_MANIFESTS_REF:-main}"
    local token
    local source_used
    local tmp_root
    local work_dir
    local archive_file
    local headers_file
    local extract_dir
    local staging_dir
    local backup_dir
    local -a source_repos=()

    while [[ "$#" -gt 0 ]]; do
        arg="$1"
        case "$arg" in
            --help|-h)
                _update_usage
                return 0
                ;;
            *)
                fail "Unknown update option: ${arg}"
                ;;
        esac
        shift
    done

    _update_validate_source "$repo" "$ref"
    _update_require_tools

    if ! token="$(_update_auth_token)"; then
        fail "Authentication is required to update manifests. Set GITHUB_TOKEN or run: gh auth login"
    fi

    tmp_root="${TT_HOME}/.tmp"
    mkdir -p "$tmp_root" || fail "Failed to create update temp directory: ${tmp_root}"
    work_dir="$(mktemp -d "${tmp_root}/update.XXXXXX")" || \
        fail "Failed to create update temp directory."
    _update_enable_cleanup "$work_dir"

    archive_file="${work_dir}/manifests.tar.gz"
    headers_file="${work_dir}/headers"
    extract_dir="${work_dir}/extract"
    staging_dir="${work_dir}/staging"
    backup_dir="${work_dir}/backup"

    mapfile -t source_repos < <(_update_source_repos "$repo")
    if [[ "${#source_repos[@]}" -eq 0 ]]; then
        fail "No manifest sources configured."
    fi

    _update_write_headers "$headers_file" "$token"
    _update_fetch_archive "$archive_file" "$headers_file" "$ref" "${source_repos[@]}"
    source_used="$TT_UPDATE_SOURCE_USED"
    _update_stage_manifests "$archive_file" "$extract_dir" "$staging_dir"
    _update_apply_staged_manifests "$staging_dir" "$backup_dir"
    _update_mark_success

    _update_disable_cleanup
    rm -rf -- "$work_dir"
    log_info "Updated manifests from ${source_used}@${ref}."
}

maybe_update_manifests() {
    local marker

    marker="$(_update_last_update_file)"
    [[ -f "$marker" ]] || return 0

    if _update_cache_is_fresh; then
        return 0
    fi

    log_info "Manifest cache is stale; refreshing manifests."
    if ! ( update_manifests ); then
        log_warn "Automatic manifest update failed; continuing with cached manifests."
    fi
}
