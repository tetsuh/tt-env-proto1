#!/usr/bin/env bash
# Install command helpers for tt-env.
#
# Public symbols:
#   - install_release [--dry-run] [--force] <release>

if [[ -n "${TT_INSTALL_LOADED:-}" ]]; then
    return 0
fi
TT_INSTALL_LOADED=1

INSTALL_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_ROOT="$(cd "${INSTALL_LIB_DIR}/.." && pwd)"
# shellcheck disable=SC1091
source "${INSTALL_LIB_DIR}/core.sh"
# shellcheck disable=SC1091
source "${INSTALL_LIB_DIR}/security.sh"
# shellcheck disable=SC1091
source "${INSTALL_LIB_DIR}/manifest_parser.sh"
# shellcheck disable=SC1091
source "${INSTALL_LIB_DIR}/package_manager.sh"
# shellcheck disable=SC1091
source "${INSTALL_LIB_DIR}/shims.sh"

_install_usage() {
    cat <<'EOF'
Usage:
  tt-env install [--dry-run] [--force] <release>
EOF
}

_install_validate_release_name() {
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

_install_stack_manifest_path() {
    local release="$1"
    local tt_home_manifest="${TT_HOME}/releases/${release}.json"
    local bundled_manifest="${INSTALL_ROOT}/releases/${release}.json"

    if [[ -f "$tt_home_manifest" ]]; then
        printf '%s\n' "$tt_home_manifest"
    elif [[ -f "$bundled_manifest" ]]; then
        printf '%s\n' "$bundled_manifest"
    else
        fail "Release manifest not found for ${release}."
    fi
}

_install_os_manifest_path() {
    local os_id="$1"
    local os_version="$2"
    local manifest_name="${os_id}-${os_version}.env"
    local tt_home_manifest="${TT_HOME}/manifests/${manifest_name}"
    local bundled_manifest="${INSTALL_ROOT}/manifests/${manifest_name}"

    if [[ -f "$tt_home_manifest" ]]; then
        printf '%s\n' "$tt_home_manifest"
    elif [[ -f "$bundled_manifest" ]]; then
        printf '%s\n' "$bundled_manifest"
    else
        fail "OS manifest not found for ${os_id} ${os_version}."
    fi
}

_install_require_sha256_tool() {
    command_exists sha256sum || command_exists shasum
}

_install_require_download_tools() {
    local rollback_dir="$1"

    if ! command_exists curl; then
        _install_rollback_fail "$rollback_dir" "curl is required to download release artifacts."
    fi

    if ! _install_require_sha256_tool; then
        _install_rollback_fail "$rollback_dir" "sha256sum or shasum is required to verify downloaded artifacts."
    fi
}

_install_rollback_fail() {
    local rollback_dir="$1"
    shift

    rm -rf -- "$rollback_dir"
    fail "$@"
}

_install_enable_partial_cleanup() {
    TT_INSTALL_CLEANUP_PARTIAL="$1"
    trap 'if [[ -n "${TT_INSTALL_CLEANUP_PARTIAL:-}" ]]; then rm -rf -- "$TT_INSTALL_CLEANUP_PARTIAL"; fi' EXIT
}

_install_disable_partial_cleanup() {
    unset TT_INSTALL_CLEANUP_PARTIAL
}

_install_component_names() {
    printf '%s\n' "${!TT_STACK_COMPONENTS[@]}" | sort
}

_install_download_components() {
    local dry_run="$1"
    local target_dir="$2"
    local artifacts_dir="${target_dir}/artifacts"
    local -a components=()
    local -a curl_args=()
    local component
    local download_url
    local expected_sha256
    local actual_sha256
    local artifact_path

    mapfile -t components < <(_install_component_names)

    if [[ "${#components[@]}" -eq 0 ]]; then
        fail "Stack manifest does not define downloadable components."
    fi

    for component in "${components[@]}"; do
        download_url="${TT_STACK_COMPONENT_DOWNLOAD_URLS[$component]:-}"
        expected_sha256="${TT_STACK_COMPONENT_SHA256S[$component]:-}"

        if [[ -z "$download_url" || -z "$expected_sha256" ]]; then
            fail "Stack component ${component} requires download_url and sha256 when system package installation is disabled."
        fi

        if [[ "$dry_run" -eq 1 ]]; then
            log_info "[dry-run] Would download ${component} from ${download_url}"
        fi
    done

    if [[ "$dry_run" -eq 1 ]]; then
        return 0
    fi

    _install_require_download_tools "$target_dir"
    mkdir -p "$artifacts_dir" || fail "Failed to create artifacts directory: ${artifacts_dir}"

    curl_args=(--fail --location --retry 3)
    if [[ -t 2 ]]; then
        curl_args+=(--progress-bar)
    else
        curl_args+=(--silent --show-error)
    fi

    for component in "${components[@]}"; do
        download_url="${TT_STACK_COMPONENT_DOWNLOAD_URLS[$component]:-}"
        expected_sha256="${TT_STACK_COMPONENT_SHA256S[$component],,}"
        artifact_path="${artifacts_dir}/${component}"

        log_info "Downloading ${component} from ${download_url}"
        curl "${curl_args[@]}" --output "$artifact_path" "$download_url" || \
            _install_rollback_fail "$target_dir" "Failed to download ${component} from ${download_url}"

        actual_sha256="$(calculate_sha256 "$artifact_path")"
        actual_sha256="${actual_sha256,,}"
        if [[ "$actual_sha256" != "$expected_sha256" ]]; then
            _install_rollback_fail \
                "$target_dir" \
                "sha256 mismatch for ${component}: expected ${expected_sha256}, got ${actual_sha256}"
        fi
    done
}

_install_path_is_tt_managed() {
    local path="$1"
    local tt_home_real="$2"

    case "$path" in
        "${TT_HOME}"|"${TT_HOME}"/*)
            return 0
            ;;
    esac

    if [[ -n "$tt_home_real" ]]; then
        case "$path" in
            "$tt_home_real"|"$tt_home_real"/*)
                return 0
                ;;
        esac
    fi

    return 1
}

_install_candidate_is_tt_managed() {
    local candidate="$1"
    local tt_home_real="$2"
    local resolved_candidate=""
    local path
    local -a candidate_paths=()

    candidate_paths=("$candidate")
    if command_exists readlink; then
        resolved_candidate="$(readlink -f -- "$candidate" 2>/dev/null || true)"
        [[ -n "$resolved_candidate" ]] && candidate_paths+=("$resolved_candidate")
    fi

    for path in "${candidate_paths[@]}"; do
        if _install_path_is_tt_managed "$path" "$tt_home_real"; then
            return 0
        fi
    done

    return 1
}

_install_path_entry_is_preferred_system_dir() {
    local path_entry="$1"
    local system_dirs="${TT_INSTALL_SYSTEM_COMMAND_DIRS:-/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin}"
    local system_dir
    local -a system_dir_entries=()

    IFS=':' read -r -a system_dir_entries <<<"$system_dirs"
    for system_dir in "${system_dir_entries[@]}"; do
        [[ -n "$system_dir" ]] || continue
        if [[ "$path_entry" == "$system_dir" ]]; then
            return 0
        fi
    done

    return 1
}

_install_find_system_command() {
    local command_name="$1"
    local tt_home_real="$2"
    local path_entry
    local candidate
    local -a path_entries=()

    IFS=':' read -r -a path_entries <<<"${PATH:-}"
    for path_entry in "${path_entries[@]}"; do
        [[ "$path_entry" == /* ]] || continue
        _install_path_entry_is_preferred_system_dir "$path_entry" || continue
        candidate="${path_entry%/}/${command_name}"

        if _install_candidate_is_tt_managed "$candidate" "$tt_home_real"; then
            continue
        fi

        if [[ -f "$candidate" && -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

_install_write_python_command_wrapper() {
    local link_path="$1"
    local command_kind="$2"
    local command_value="$3"
    local venv_subdir="$TT_PACKAGE_MANAGER_VENV_SUBDIR"
    local quoted_command_value
    local command_assignment

    printf -v quoted_command_value '%q' "$command_value"
    case "$command_kind" in
        absolute)
            command_assignment="TARGET_COMMAND=${quoted_command_value}"
            ;;
        venv)
            command_assignment=$(printf "VENV_COMMAND_NAME=%s\nTARGET_COMMAND=\"\${VENV_DIR}/bin/\${VENV_COMMAND_NAME}\"" "$quoted_command_value")
            ;;
        *)
            return 1
            ;;
    esac

    rm -f -- "$link_path" || return 1
    cat >"$link_path" <<EOF || return 1
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
VERSION_DIR="\$(cd "\${SCRIPT_DIR}/.." && pwd)"
VENV_DIR="\${VERSION_DIR}/${venv_subdir}"
VENV_PYTHON="\${VENV_DIR}/bin/python"

VIRTUAL_ENV="\${VENV_DIR}"
PATH="\${VENV_DIR}/bin\${PATH:+:\${PATH}}"
export VIRTUAL_ENV PATH

${command_assignment}
first_line=""
IFS= read -r -n 128 first_line <"\$TARGET_COMMAND" || true
if [[ -x "\$VENV_PYTHON" && "\$first_line" == '#!'*python* ]]; then
  exec "\$VENV_PYTHON" "\$TARGET_COMMAND" "\$@"
fi

exec "\$TARGET_COMMAND" "\$@"
EOF
    chmod 755 "$link_path"
}

_install_write_python_package_wrapper() {
    local command_path="$1"
    local link_path="$2"

    _install_write_python_command_wrapper "$link_path" absolute "$command_path"
}

_install_write_venv_command_wrapper() {
    local command_name="$1"
    local link_path="$2"

    _install_write_python_command_wrapper "$link_path" venv "$command_name"
}

_install_create_system_bin_links() {
    local dry_run="$1"
    local target_dir="$2"
    local bin_dir="${target_dir}/bin"
    local command_name
    local command_path
    local link_path
    local venv_command_path
    local tt_home_real=""

    if [[ -d "$TT_HOME" ]]; then
        tt_home_real="$(cd "$TT_HOME" && pwd -P)" || tt_home_real=""
    fi

    if [[ "$dry_run" -eq 0 ]]; then
        mkdir -p "$bin_dir" || _install_rollback_fail "$target_dir" "Failed to create bin directory: ${bin_dir}"
    fi

    # package_manager.sh owns the mapping from commands to release-local pip packages.
    for command_name in "${TT_SHIM_COMMANDS[@]}"; do
        link_path="${bin_dir}/${command_name}"
        if [[ -n "${TT_STACK_GIT_COMPONENTS_URL[$command_name]:-}" || -n "${TT_STACK_CONTAINER_COMPONENTS_IMAGE_URL[$command_name]:-}" ]]; then
            continue
        fi
        venv_command_path="${target_dir}/${TT_PACKAGE_MANAGER_VENV_SUBDIR}/bin/${command_name}"
        if [[ "$dry_run" -eq 1 ]] && package_manager_command_needs_pip_packages "$command_name"; then
            log_info "[dry-run] Would use venv command if installed: ${venv_command_path}"
        elif [[ "$dry_run" -eq 0 && -x "$venv_command_path" ]]; then
            _install_write_venv_command_wrapper "$command_name" "$link_path" || \
                _install_rollback_fail "$target_dir" "Failed to create venv command wrapper for ${command_name}: ${link_path}"
            continue
        fi
        if command_path="$(_install_find_system_command "$command_name" "$tt_home_real")"; then
            if [[ "$dry_run" -eq 1 ]]; then
                if package_manager_command_needs_pip_packages "$command_name"; then
                    log_info "[dry-run] Would create Python virtualenv wrapper: ${link_path} -> ${command_path}"
                else
                    log_info "[dry-run] Would create bin link: ${link_path} -> ${command_path}"
                fi
                continue
            fi
            if package_manager_command_needs_pip_packages "$command_name" && [[ -d "${target_dir}/${TT_PACKAGE_MANAGER_VENV_SUBDIR}" ]]; then
                _install_write_python_package_wrapper "$command_path" "$link_path" || \
                    _install_rollback_fail "$target_dir" "Failed to create Python virtualenv wrapper for ${command_name}: ${link_path}"
            else
                ln -sf -- "$command_path" "$link_path" || \
                _install_rollback_fail "$target_dir" "Failed to create bin link for ${command_name}: ${link_path}"
            fi
        elif [[ "$dry_run" -eq 1 ]]; then
            if package_manager_command_needs_pip_packages "$command_name"; then
                log_info "[dry-run] Would create Python virtualenv wrapper for ${command_name} after system package install."
            else
                log_info "[dry-run] Would create bin link for ${command_name} after system package install."
            fi
        elif ! shim_command_is_optional "$command_name"; then
            log_warn "Installed command not found in PATH: ${command_name}"
        fi
    done
}

_install_git_and_container_components() {
    local dry_run="$1"
    local target_dir="$2"
    local src_dir="${target_dir}/src"
    local bin_dir="${target_dir}/bin"
    local venv_subdir="$TT_PACKAGE_MANAGER_VENV_SUBDIR"
    local component
    local url
    local version
    local component_dir
    local wrapper_path
    local entrypoint
    local image_url
    local image_tag

    # 1. Git Components (tt-studio, tt-inference-server, etc.)
    if [[ "${#TT_STACK_GIT_COMPONENTS_URL[@]}" -gt 0 ]]; then
        if [[ "$dry_run" -eq 1 ]]; then
            log_info "[dry-run] Would create src directory: ${src_dir}"
        else
            mkdir -p "$src_dir" || fail "Failed to create src directory: ${src_dir}"
            mkdir -p "$bin_dir" || fail "Failed to create bin directory: ${bin_dir}"
        fi

        # Check if git is installed (once, outside the loop)
        if [[ "$dry_run" -ne 1 ]]; then
            command_exists git || fail "git is required to install git components."
        fi

        for component in "${!TT_STACK_GIT_COMPONENTS_URL[@]}"; do
            url="${TT_STACK_GIT_COMPONENTS_URL[$component]}"
            version="${TT_STACK_GIT_COMPONENTS_VERSION[$component]}"
            entrypoint="${TT_STACK_GIT_COMPONENTS_ENTRYPOINT[$component]:-run.py}"
            component_dir="${src_dir}/${component}"
            wrapper_path="${bin_dir}/${component}"

            if [[ "$dry_run" -eq 1 ]]; then
                log_info "[dry-run] Would git clone ${url} at ${version} into ${component_dir}"
                log_info "[dry-run] Would create git component wrapper: ${wrapper_path}"
                continue
            fi

            if [[ -d "$component_dir" ]]; then
                # Verify existing git remote URL matches the stack manifest
                local current_remote_url=""
                if current_remote_url="$(cd "$component_dir" && git remote get-url origin 2>/dev/null)"; then
                    # Normalize URLs (e.g. removing trailing .git or spaces) to compare
                    local normalized_current="${current_remote_url%.git}"
                    local normalized_manifest="${url%.git}"
                    if [[ "$normalized_current" != "$normalized_manifest" ]]; then
                        log_warn "Git remote URL mismatch for ${component}. Expected: ${url}, Found: ${current_remote_url}. Re-cloning..."
                        rm -rf -- "$component_dir"
                    fi
                else
                    log_warn "Invalid git repository at ${component_dir}. Re-cloning..."
                    rm -rf -- "$component_dir"
                fi
            fi

            if [[ ! -d "$component_dir" ]]; then
                log_info "Cloning git component ${component} from ${url}"
                git clone "$url" "$component_dir" || fail "Failed to clone ${component} from ${url}"
            fi

            ( 
                cd "$component_dir" && \
                git fetch --all && \
                git checkout "$version"
            ) || fail "Failed to checkout ${component} to version ${version}"

            log_info "Creating wrapper script for git component ${component} at ${wrapper_path}"
            cat >"$wrapper_path" <<EOF || fail "Failed to write wrapper script: ${wrapper_path}"
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
VERSION_DIR="\$(cd "\${SCRIPT_DIR}/.." && pwd)"
VENV_DIR="\${VERSION_DIR}/${venv_subdir}"
VENV_PYTHON="\${VENV_DIR}/bin/python"

VIRTUAL_ENV="\${VENV_DIR}"
PATH="\${VENV_DIR}/bin\${PATH:+:\${PATH}}"
export VIRTUAL_ENV PATH

# Set PYTHONPATH to the component src directory to allow imports
PYTHONPATH="\${VERSION_DIR}/src/${component}\${PYTHONPATH:+:\${PYTHONPATH}}"
export PYTHONPATH

TARGET_COMMAND="\${VERSION_DIR}/src/${component}/${entrypoint}"

first_line=""
IFS= read -r -n 128 first_line <"\$TARGET_COMMAND" || true
if [[ -x "\$VENV_PYTHON" && ( "\$first_line" == '#!'*python* || "\$TARGET_COMMAND" == *.py ) ]]; then
  exec "\$VENV_PYTHON" "\$TARGET_COMMAND" "\$@"
fi

exec "\$TARGET_COMMAND" "\$@"
EOF
            chmod 755 "$wrapper_path" || fail "Failed to make wrapper executable: ${wrapper_path}"
        done
    fi

    # 2. Container Components (tt-metalium-models, etc.)
    if [[ "${#TT_STACK_CONTAINER_COMPONENTS_IMAGE_URL[@]}" -gt 0 ]]; then
        if [[ "$dry_run" -eq 1 ]]; then
            log_info "[dry-run] Would create bin directory: ${bin_dir}"
        else
            mkdir -p "$bin_dir" || fail "Failed to create bin directory: ${bin_dir}"
        fi

        for component in "${!TT_STACK_CONTAINER_COMPONENTS_IMAGE_URL[@]}"; do
            image_url="${TT_STACK_CONTAINER_COMPONENTS_IMAGE_URL[$component]}"
            image_tag="${TT_STACK_CONTAINER_COMPONENTS_IMAGE_TAG[$component]}"
            wrapper_path="${bin_dir}/${component}"

            if [[ "$dry_run" -eq 1 ]]; then
                log_info "[dry-run] Would create container component wrapper for ${component} using image ${image_url}:${image_tag}"
                continue
            fi

            log_info "Creating container component wrapper for ${component} at ${wrapper_path}"
            cat >"$wrapper_path" <<EOF || fail "Failed to write container wrapper script: ${wrapper_path}"
#!/usr/bin/env bash
# Wrapper script for ${component} using OCI container runtime

# Verify docker is installed
if ! command -v docker >/dev/null 2>&1; then
    echo "[ERROR] docker command not found. Please install Docker to run this tool." >&2
    exit 1
fi

# Tenstorrent hardware preflight check
if [[ ! -c /dev/tenstorrent && ! -d /dev/tenstorrent ]]; then
    echo "[WARNING] Tenstorrent device /dev/tenstorrent not found. The model container may fail to run." >&2
fi

echo "================================================================================"
echo "NOTE: This container tool for tt-metalium is meant to enable users to try out"
echo "      demos, and is not meant for production use. This container is liable"
echo "      to change at any time."
echo ""
echo "      For more information see https://github.com/tenstorrent/tt-metal/issues/25602"
echo "================================================================================"

# Image configuration
METALIUM_IMAGE="${image_url}:${image_tag}"

# Determine if we should run in TTY/interactive mode
docker_flags=("--rm")
if [[ -t 0 ]]; then
    docker_flags+=("-it")
fi

# Run the command using container runtime
docker run "\${docker_flags[@]}" \\
  --privileged \\
  --volume=/dev/hugepages-1G:/dev/hugepages-1G \\
  --device=/dev/tenstorrent:/dev/tenstorrent \\
  --env=DISPLAY=\${DISPLAY} \\
  --env=HOME=/home/user \\
  --env=TERM=\${TERM:-xterm-256color} \\
  --network=host \\
  --security-opt label=disable \\
  \${METALIUM_IMAGE} "\$@"
EOF
            chmod 755 "$wrapper_path" || fail "Failed to make wrapper executable: ${wrapper_path}"
        done
    fi
}

_install_system_packages() {
    local dry_run="$1"
    local target_dir="$2"
    local os_manifest
    local detected_os_id
    local detected_os_version
    local pkg_manager
    local use_system_packages

    detect_os
    detected_os_id="${OS_ID:-}"
    detected_os_version="${OS_VERSION:-}"
    os_manifest="$(_install_os_manifest_path "$detected_os_id" "$detected_os_version")"
    parse_env_manifest "$os_manifest"

    pkg_manager="${TT_MANIFEST_SCALARS[PKG_MANAGER]:-}"
    use_system_packages="${TT_MANIFEST_SCALARS[USE_SYSTEM_PACKAGES]:-${TT_MANIFEST_SCALARS[USE_PPA]:-}}"

    [[ -n "$pkg_manager" ]] || fail "OS manifest is missing PKG_MANAGER: ${os_manifest}"
    [[ -n "$use_system_packages" ]] || fail "OS manifest is missing USE_SYSTEM_PACKAGES or USE_PPA: ${os_manifest}"

    package_manager_require_supported "$pkg_manager"

    case "$use_system_packages" in
        true)
            package_manager_install_system_packages "$pkg_manager" "$dry_run"
            package_manager_install_pip_packages "$dry_run" "$target_dir"
            _install_git_and_container_components "$dry_run" "$target_dir"
            _install_create_system_bin_links "$dry_run" "$target_dir"
            ;;
        false)
            log_info "System package install path is disabled by ${os_manifest}."
            _install_download_components "$dry_run" "$target_dir"
            ;;
        *)
            fail "Invalid USE_SYSTEM_PACKAGES or USE_PPA value in ${os_manifest}: ${use_system_packages}"
            ;;
    esac
}

_install_remove_version_dir() {
    local versions_dir="$1"
    local version_dir="$2"
    local physical_versions_dir
    local physical_parent_dir

    physical_versions_dir="$(cd "$versions_dir" && pwd -P)"
    physical_parent_dir="$(cd "$(dirname "$version_dir")" && pwd -P)"

    if [[ "$physical_parent_dir" != "$physical_versions_dir" || "$version_dir" == "$versions_dir" ]]; then
        fail "Refusing to remove unsafe version directory: ${version_dir}"
    fi

    log_info "Removing existing version directory: ${version_dir}"
    rm -rf -- "$version_dir"
}

install_release() {
    local dry_run=0
    local force=0
    local release=""
    local arg

    while [[ "$#" -gt 0 ]]; do
        arg="$1"
        case "$arg" in
            --dry-run)
                dry_run=1
                ;;
            --force)
                force=1
                ;;
            --help|-h)
                _install_usage
                return 0
                ;;
            --*)
                fail "Unknown install option: ${arg}"
                ;;
            *)
                if [[ -n "$release" ]]; then
                    fail "install accepts exactly one release."
                fi
                release="$arg"
                ;;
        esac
        shift
    done

    if [[ -z "$release" ]]; then
        _install_usage >&2
        return 1
    fi

    _install_validate_release_name "$release"
    init_tt_home

    local manifest_file
    local versions_dir="${TT_HOME}/versions"
    local version_dir="${versions_dir}/${release}"
    local partial_dir="${versions_dir}/.${release}.partial"
    local installed_marker="${version_dir}/.tt-env-installed"
    local partial_installed_marker="${partial_dir}/.tt-env-installed"

    manifest_file="$(_install_stack_manifest_path "$release")"
    parse_stack_manifest "$manifest_file"

    if [[ "$TT_STACK_RELEASE" != "$release" ]]; then
        fail "Release manifest ${manifest_file} declares ${TT_STACK_RELEASE}, expected ${release}."
    fi

    if [[ -f "$installed_marker" && "$force" -eq 0 ]]; then
        log_info "Release ${release} is already installed at ${version_dir}."
        generate_shims
        return 0
    fi

    if [[ -e "$version_dir" && ! -f "$installed_marker" && "$force" -eq 0 ]]; then
        fail "Version directory exists but is not marked installed: ${version_dir}. Use --force to recreate it."
    fi

    if [[ "$dry_run" -eq 1 ]]; then
        _install_system_packages "$dry_run" "$version_dir"
        if [[ -e "$version_dir" && "$force" -eq 1 ]]; then
            log_info "[dry-run] Would remove existing version directory: ${version_dir}"
        fi
        log_info "[dry-run] Would create version directory: ${version_dir}"
        return 0
    fi

    mkdir -p "$versions_dir" || fail "Failed to create versions directory: ${versions_dir}"

    if [[ -e "$partial_dir" ]]; then
        _install_remove_version_dir "$versions_dir" "$partial_dir"
    fi

    mkdir -p "$partial_dir" || fail "Failed to create partial version directory: ${partial_dir}"
    _install_enable_partial_cleanup "$partial_dir"

    _install_system_packages "$dry_run" "$partial_dir"

    printf 'release=%s\n' "$release" >"$partial_installed_marker" || \
        _install_rollback_fail "$partial_dir" "Failed to write installed marker: ${partial_installed_marker}"

    if [[ -e "$version_dir" && "$force" -eq 1 ]]; then
        _install_remove_version_dir "$versions_dir" "$version_dir"
    fi

    mv -- "$partial_dir" "$version_dir" || \
        _install_rollback_fail "$partial_dir" "Failed to finalize version directory: ${version_dir}"

    [[ -f "$installed_marker" ]] || fail "Installed marker missing after finalizing ${version_dir}"
    _install_disable_partial_cleanup

    generate_shims
    log_info "Installed release ${release} at ${version_dir}."
}
