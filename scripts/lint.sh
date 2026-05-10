#!/usr/bin/env bash
# scripts/lint.sh - Lint shell scripts using shellcheck

set -euo pipefail

# Identify root directory
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# Use find -print0 and read -d '' to handle filenames with spaces and special characters.
# We look for:
# 1. Files ending in .sh
# 2. The tt-env executable (which has no extension)
LINT_TARGETS=()
while IFS= read -r -d '' file; do
    LINT_TARGETS+=("$file")
done < <(find . \( -name "*.sh" -o -name "tt-env" \) \
    -not -path "./.git/*" \
    -not -path "*/vendor/*" \
    -type f -print0)

if [[ ${#LINT_TARGETS[@]} -eq 0 ]]; then
    echo "No shell files found to lint."
    exit 0
fi

echo "Linting: ${LINT_TARGETS[*]}"
shellcheck "${LINT_TARGETS[@]}"
