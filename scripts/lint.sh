#!/usr/bin/env bash
# scripts/lint.sh - Lint shell scripts using shellcheck

set -euo pipefail

# Identify root directory
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# Explicitly list files that might not have .sh extension but are shell scripts
EXPLICIT_FILES=(
    "install.sh"
    "bin/tt-env"
)

# Find all .sh files in the repo, excluding .git and vendor directories
# shellcheck disable=SC2207
SH_FILES=($(find . -name "*.sh" -not -path "./.git/*" -not -path "*/vendor/*"))

ALL_FILES=("${EXPLICIT_FILES[@]}" "${SH_FILES[@]}")

# Filter to only existing files
LINT_TARGETS=()
for f in "${ALL_FILES[@]}"; do
    if [[ -f "$f" ]]; then
        LINT_TARGETS+=("$f")
    fi
done

if [[ ${#LINT_TARGETS[@]} -eq 0 ]]; then
    echo "No shell files found to lint."
    exit 0
fi

echo "Linting: ${LINT_TARGETS[*]}"
shellcheck "${LINT_TARGETS[@]}"
