#!/usr/bin/env bash
# Zero-dependency bootstrap script for tt-env.

set -euo pipefail

fail() {
    printf '[ERROR] %s\n' "$*" >&2
    exit 1
}

log_info() {
    printf '[INFO] %s\n' "$*"
}

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "${TT_HOME:-}" ]]; then
    [[ -z "${HOME:-}" ]] && fail "HOME environment variable is not set."
    TT_HOME="${HOME}/.tt-env"
fi
export TT_HOME

TT_BIN_DIR="${TT_HOME}/bin"
TT_LIB_DIR="${TT_HOME}/lib"

[[ -f "${REPO_DIR}/bin/tt-env" ]] || fail "Missing ${REPO_DIR}/bin/tt-env"
[[ -f "${REPO_DIR}/VERSION" ]] || fail "Missing ${REPO_DIR}/VERSION"
[[ -d "${REPO_DIR}/lib" ]] || fail "Missing ${REPO_DIR}/lib"

log_info "Installing tt-env to ${TT_HOME}"

mkdir -p "${TT_HOME}/"{bin,lib,manifests,releases,versions,shims} || \
    fail "Failed to initialize TT_HOME directory layout at ${TT_HOME}"

install -m 755 "${REPO_DIR}/bin/tt-env" "${TT_BIN_DIR}/tt-env"
install -m 644 "${REPO_DIR}/VERSION" "${TT_HOME}/VERSION"

while IFS= read -r -d '' lib_file; do
    install -m 644 "$lib_file" "${TT_LIB_DIR}/"
done < <(find "${REPO_DIR}/lib" -maxdepth 1 -type f -name "*.sh" -print0)

log_info "tt-env installed successfully."

cat <<EOF

Add tt-env to your PATH:

  bash/zsh:
    export PATH="${TT_BIN_DIR}:\$PATH"

  fish:
    fish_add_path "${TT_BIN_DIR}"

Verify the installation:

  tt-env --version
EOF
