#!/usr/bin/env bash
# scripts/lint.sh - Lint shell scripts using shellcheck

set -euo pipefail

# Identify root directory
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

check_manifest_parser_no_source() {
    local manifest_parser="${TT_LINT_MANIFEST_PARSER_FILE:-./lib/manifest_parser.sh}"
    local violations

    [[ -f "$manifest_parser" ]] || {
        echo "Manifest parser not found: ${manifest_parser}" >&2
        exit 1
    }

    violations="$(awk '
        /^[[:space:]]*(#|$)/ { next }
        /(^|[;&|[:space:](){!])(source|\.)([[:space:]]|$)/ {
            print FILENAME ":" FNR ":" $0
        }
    ' "$manifest_parser")"

    if [[ -n "$violations" ]]; then
        echo "lib/manifest_parser.sh must not invoke source or ."
        printf '%s\n' "$violations"
        exit 1
    fi
}

check_manifest_parser_no_source
if [[ "${TT_LINT_NO_SOURCE_ONLY:-0}" == "1" ]]; then
    exit 0
fi

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
