#!/usr/bin/env bash
# scripts/test.sh - Run bats tests

set -euo pipefail

# Identify root directory
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# Path to bats executable
BATS="$ROOT_DIR/tests/bats/vendor/bats-core/bin/bats"

if [[ ! -f "$BATS" ]]; then
    echo "Error: bats-core not found at $BATS"
    echo "Please run: git submodule update --init"
    exit 1
fi

echo "Running tests..."
# Use bash to run bats to ensure it works on Windows/MSYS
# Only run tests in tests/bats/ and skip the vendor directory
bash "$BATS" tests/bats/*.bats
