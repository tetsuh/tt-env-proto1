#!/usr/bin/env bats

setup() {
  MANIFEST_PARSER="${BATS_TEST_DIRNAME}/../../lib/manifest_parser.sh"
}

write_stack_manifest() {
  local manifest_file="$1"
  cat >"$manifest_file" <<'EOF'
{
  "release": "2026.05.16",
  "description": "Tenstorrent proto sample stack 2026.05.16",
  "components": {
    "tt-kmd": "ttkmd-2.8.0",
    "tt-smi": "v5.2.0",
    "firmware": "v19.6.0",
    "tt-metal": "v0.70.1"
  },
  "system_packages": {
    "kmd": "2.8.0",
    "smi": "5.0.1",
    "flash": "3.6.5",
    "topology": "1.2.19"
  },
  "python_packages": {
    "tt-umd": "0.9.5",
    "textual": "0.59.0",
    "elasticsearch": "8.11.0"
  }
}
EOF
}

write_download_stack_manifest() {
  local manifest_file="$1"
  cat >"$manifest_file" <<'EOF'
{
  "release": "2026.05.16",
  "description": "Tenstorrent proto sample stack 2026.05.16",
  "components": {
    "tt-kmd": {
      "version": "ttkmd-2.8.0",
      "download_url": "https://example.invalid/tt-kmd",
      "sha256": "1111111111111111111111111111111111111111111111111111111111111111"
    },
    "tt-smi": {
      "version": "v5.2.0",
      "download_url": "https://example.invalid/tt-smi",
      "sha256": "2222222222222222222222222222222222222222222222222222222222222222"
    },
    "firmware": {
      "version": "v19.6.0",
      "download_url": "https://example.invalid/firmware",
      "sha256": "3333333333333333333333333333333333333333333333333333333333333333"
    },
    "tt-metal": {
      "version": "v0.70.1",
      "download_url": "https://example.invalid/tt-metal",
      "sha256": "4444444444444444444444444444444444444444444444444444444444444444"
    }
  }
}
EOF
}

@test "parse_stack_manifest fallback extracts release metadata and components" {
  manifest_file="${BATS_TEST_TMPDIR}/2026.05.16.json"
  write_stack_manifest "$manifest_file"

  run env TT_MANIFEST_DISABLE_JQ=1 bash -c '
    source "$1"
    parse_stack_manifest "$2"
    printf "%s\n" "$TT_STACK_RELEASE"
    printf "%s\n" "$TT_STACK_DESCRIPTION"
    printf "%s\n" "${TT_STACK_COMPONENTS[tt-kmd]}"
    printf "%s\n" "${TT_STACK_COMPONENTS[tt-metal]}"
    printf "%s\n" "${TT_STACK_SYSTEM_PACKAGES[kmd]}"
    printf "%s\n" "${TT_STACK_SYSTEM_PACKAGES[smi]}"
    printf "%s\n" "${TT_STACK_SYSTEM_PACKAGES[flash]}"
    printf "%s\n" "${TT_STACK_SYSTEM_PACKAGES[topology]}"
    printf "%s\n" "${TT_STACK_PYTHON_PACKAGES[tt-umd]}"
    printf "%s\n" "${TT_STACK_PYTHON_PACKAGES[textual]}"
    printf "%s\n" "${TT_STACK_PYTHON_PACKAGES[elasticsearch]}"
  ' bash "$MANIFEST_PARSER" "$manifest_file"

  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "2026.05.16" ]
  [ "${lines[1]}" = "Tenstorrent proto sample stack 2026.05.16" ]
  [ "${lines[2]}" = "ttkmd-2.8.0" ]
  [ "${lines[3]}" = "v0.70.1" ]
  [ "${lines[4]}" = "2.8.0" ]
  [ "${lines[5]}" = "5.0.1" ]
  [ "${lines[6]}" = "3.6.5" ]
  [ "${lines[7]}" = "1.2.19" ]
  [ "${lines[8]}" = "0.9.5" ]
  [ "${lines[9]}" = "0.59.0" ]
  [ "${lines[10]}" = "8.11.0" ]
}

@test "parse_stack_manifest jq and fallback paths return identical results" {
  command -v jq >/dev/null 2>&1 || skip "jq not available"

  manifest_file="${BATS_TEST_TMPDIR}/2026.05.16.json"
  write_stack_manifest "$manifest_file"

  run bash -c '
    source "$1"
    parse_stack_manifest "$2"
    printf "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n" \
      "$TT_STACK_RELEASE" \
      "$TT_STACK_DESCRIPTION" \
      "${TT_STACK_COMPONENTS[tt-kmd]}" \
      "${TT_STACK_COMPONENTS[tt-smi]}" \
      "${TT_STACK_COMPONENTS[firmware]}" \
      "${TT_STACK_COMPONENTS[tt-metal]}" \
      "${TT_STACK_SYSTEM_PACKAGES[kmd]}" \
      "${TT_STACK_SYSTEM_PACKAGES[smi]}" \
      "${TT_STACK_SYSTEM_PACKAGES[flash]}" \
      "${TT_STACK_SYSTEM_PACKAGES[topology]}" \
      "${TT_STACK_PYTHON_PACKAGES[tt-umd]}" \
      "${TT_STACK_PYTHON_PACKAGES[textual]}" \
      "${TT_STACK_PYTHON_PACKAGES[elasticsearch]}"
  ' bash "$MANIFEST_PARSER" "$manifest_file"
  [ "$status" -eq 0 ]
  jq_output="$output"

  run env TT_MANIFEST_DISABLE_JQ=1 bash -c '
    source "$1"
    parse_stack_manifest "$2"
    printf "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n" \
      "$TT_STACK_RELEASE" \
      "$TT_STACK_DESCRIPTION" \
      "${TT_STACK_COMPONENTS[tt-kmd]}" \
      "${TT_STACK_COMPONENTS[tt-smi]}" \
      "${TT_STACK_COMPONENTS[firmware]}" \
      "${TT_STACK_COMPONENTS[tt-metal]}" \
      "${TT_STACK_SYSTEM_PACKAGES[kmd]}" \
      "${TT_STACK_SYSTEM_PACKAGES[smi]}" \
      "${TT_STACK_SYSTEM_PACKAGES[flash]}" \
      "${TT_STACK_SYSTEM_PACKAGES[topology]}" \
      "${TT_STACK_PYTHON_PACKAGES[tt-umd]}" \
      "${TT_STACK_PYTHON_PACKAGES[textual]}" \
      "${TT_STACK_PYTHON_PACKAGES[elasticsearch]}"
  ' bash "$MANIFEST_PARSER" "$manifest_file"
  [ "$status" -eq 0 ]
  [ "$output" = "$jq_output" ]
}

@test "parse_stack_manifest extracts object component download metadata" {
  manifest_file="${BATS_TEST_TMPDIR}/download.json"
  write_download_stack_manifest "$manifest_file"

  run env TT_MANIFEST_DISABLE_JQ=1 bash -c '
    source "$1"
    parse_stack_manifest "$2"
    printf "%s\n" "${TT_STACK_COMPONENTS[tt-kmd]}"
    printf "%s\n" "${TT_STACK_COMPONENT_DOWNLOAD_URLS[tt-kmd]}"
    printf "%s\n" "${TT_STACK_COMPONENT_SHA256S[tt-kmd]}"
  ' bash "$MANIFEST_PARSER" "$manifest_file"

  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "ttkmd-2.8.0" ]
  [ "${lines[1]}" = "https://example.invalid/tt-kmd" ]
  [ "${lines[2]}" = "1111111111111111111111111111111111111111111111111111111111111111" ]
}

@test "parse_stack_manifest jq and fallback paths return identical object metadata" {
  command -v jq >/dev/null 2>&1 || skip "jq not available"

  manifest_file="${BATS_TEST_TMPDIR}/download.json"
  write_download_stack_manifest "$manifest_file"

  run bash -c '
    source "$1"
    parse_stack_manifest "$2"
    printf "%s|%s|%s\n" \
      "${TT_STACK_COMPONENTS[tt-smi]}" \
      "${TT_STACK_COMPONENT_DOWNLOAD_URLS[tt-smi]}" \
      "${TT_STACK_COMPONENT_SHA256S[tt-smi]}"
  ' bash "$MANIFEST_PARSER" "$manifest_file"
  [ "$status" -eq 0 ]
  jq_output="$output"

  run env TT_MANIFEST_DISABLE_JQ=1 bash -c '
    source "$1"
    parse_stack_manifest "$2"
    printf "%s|%s|%s\n" \
      "${TT_STACK_COMPONENTS[tt-smi]}" \
      "${TT_STACK_COMPONENT_DOWNLOAD_URLS[tt-smi]}" \
      "${TT_STACK_COMPONENT_SHA256S[tt-smi]}"
  ' bash "$MANIFEST_PARSER" "$manifest_file"
  [ "$status" -eq 0 ]
  [ "$output" = "$jq_output" ]
}

@test "parse_stack_manifest resolves container component refs" {
  manifest_file="${BATS_TEST_TMPDIR}/container-ref.json"
  cat >"$manifest_file" <<'EOF'
{
  "release": "2026.05.16",
  "components": {
    "tt-kmd": "ttkmd-2.8.0",
    "tt-smi": "v5.2.0",
    "firmware": "v19.6.0",
    "tt-metal": "v0.70.1"
  },
  "container_components": {
    "tt-metalium": {
      "ref": "tt-metalium-ubuntu24"
    },
    "tt-metalium-ubuntu24": {
      "image_url": "ghcr.io/tenstorrent/tt-metal/tt-metalium-ubuntu-24.04-release-amd64",
      "image_tag": "sha256:ead7b800bdb6bebb9425c377222314447c5b2052f6e8b1e3c9caa1818cb7d8c4"
    }
  }
}
EOF

  run env TT_MANIFEST_DISABLE_JQ=1 bash -c '
    source "$1"
    parse_stack_manifest "$2"
    printf "%s\n" "${TT_STACK_CONTAINER_COMPONENTS_IMAGE_URL[tt-metalium]}"
    printf "%s\n" "${TT_STACK_CONTAINER_COMPONENTS_IMAGE_TAG[tt-metalium]}"
  ' bash "$MANIFEST_PARSER" "$manifest_file"

  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "ghcr.io/tenstorrent/tt-metal/tt-metalium-ubuntu-24.04-release-amd64" ]
  [ "${lines[1]}" = "sha256:ead7b800bdb6bebb9425c377222314447c5b2052f6e8b1e3c9caa1818cb7d8c4" ]

  command -v jq >/dev/null 2>&1 || skip "jq not available"
  run bash -c '
    source "$1"
    parse_stack_manifest "$2"
    printf "%s|%s\n" "${TT_STACK_CONTAINER_COMPONENTS_IMAGE_URL[tt-metalium]}" "${TT_STACK_CONTAINER_COMPONENTS_IMAGE_TAG[tt-metalium]}"
  ' bash "$MANIFEST_PARSER" "$manifest_file"

  [ "$status" -eq 0 ]
  [ "$output" = "ghcr.io/tenstorrent/tt-metal/tt-metalium-ubuntu-24.04-release-amd64|sha256:ead7b800bdb6bebb9425c377222314447c5b2052f6e8b1e3c9caa1818cb7d8c4" ]
}

@test "parse_stack_manifest rejects object components with invalid sha256" {
  manifest_file="${BATS_TEST_TMPDIR}/bad-sha.json"
  write_download_stack_manifest "$manifest_file"
  sed -i 's/1111111111111111111111111111111111111111111111111111111111111111/not-a-sha/' "$manifest_file"

  run env TT_MANIFEST_DISABLE_JQ=1 bash -c 'source "$1"; parse_stack_manifest "$2"' bash "$MANIFEST_PARSER" "$manifest_file"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Invalid stack component sha256"* ]]
}

@test "parse_stack_manifest rejects object components with unknown fields" {
  manifest_file="${BATS_TEST_TMPDIR}/unknown-field.json"
  cat >"$manifest_file" <<'EOF'
{
  "release": "2026.05.16",
  "components": {
    "tt-kmd": {
      "version": "ttkmd-2.8.0",
      "download_url": "https://example.invalid/tt-kmd",
      "sha256": "1111111111111111111111111111111111111111111111111111111111111111",
      "unexpected": "value"
    },
    "tt-smi": "v5.2.0",
    "firmware": "v19.6.0",
    "tt-metal": "v0.70.1"
  }
}
EOF

  run env TT_MANIFEST_DISABLE_JQ=1 bash -c 'source "$1"; parse_stack_manifest "$2"' bash "$MANIFEST_PARSER" "$manifest_file"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unsupported stack manifest shape"* ]]
}

@test "parse_stack_manifest fallback rejects unknown JSON shapes" {
  manifest_file="${BATS_TEST_TMPDIR}/bad.json"
  cat >"$manifest_file" <<'EOF'
{
  "release": "2026.05.16",
  "components": []
}
EOF

  run env TT_MANIFEST_DISABLE_JQ=1 bash -c 'source "$1"; parse_stack_manifest "$2"' bash "$MANIFEST_PARSER" "$manifest_file"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unsupported stack manifest shape"* ]]
}

@test "parse_stack_manifest rejects invalid Python package versions" {
  manifest_file="${BATS_TEST_TMPDIR}/invalid-python-package.json"
  cat >"$manifest_file" <<'EOF'
{
  "release": "2026.05.16",
  "components": {
    "tt-kmd": "ttkmd-2.8.0",
    "tt-smi": "v5.2.0",
    "firmware": "v19.6.0",
    "tt-metal": "v0.70.1"
  },
  "python_packages": {
    "tt-umd": "0.9.5 evil"
  }
}
EOF

  run env TT_MANIFEST_DISABLE_JQ=1 bash -c 'source "$1"; parse_stack_manifest "$2"' bash "$MANIFEST_PARSER" "$manifest_file"

  [ "$status" -eq 1 ]
  [[ "$output" == *"Unsupported stack manifest shape"* ]]

  if command -v jq >/dev/null 2>&1; then
    run bash -c 'source "$1"; parse_stack_manifest "$2"' bash "$MANIFEST_PARSER" "$manifest_file"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unsupported stack manifest shape"* ]]
  fi
}

@test "parse_stack_manifest rejects invalid system package keys" {
  manifest_file="${BATS_TEST_TMPDIR}/invalid-system-package-key.json"
  cat >"$manifest_file" <<'EOF'
{
  "release": "2026.05.16",
  "components": {
    "tt-kmd": "ttkmd-2.8.0",
    "tt-smi": "v5.2.0",
    "firmware": "v19.6.0",
    "tt-metal": "v0.70.1"
  },
  "system_packages": {
    "tt-kmd": "2.8.0"
  }
}
EOF

  run env TT_MANIFEST_DISABLE_JQ=1 bash -c 'source "$1"; parse_stack_manifest "$2"' bash "$MANIFEST_PARSER" "$manifest_file"

  [ "$status" -eq 1 ]
  [[ "$output" == *"Unsupported stack manifest shape"* ]]

  if command -v jq >/dev/null 2>&1; then
    run bash -c 'source "$1"; parse_stack_manifest "$2"' bash "$MANIFEST_PARSER" "$manifest_file"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unsupported stack manifest shape"* ]]
  fi
}

@test "parse_stack_manifest rejects invalid system package versions" {
  manifest_file="${BATS_TEST_TMPDIR}/invalid-system-package-version.json"
  cat >"$manifest_file" <<'EOF'
{
  "release": "2026.05.16",
  "components": {
    "tt-kmd": "ttkmd-2.8.0",
    "tt-smi": "v5.2.0",
    "firmware": "v19.6.0",
    "tt-metal": "v0.70.1"
  },
  "system_packages": {
    "kmd": "--2.8.0"
  }
}
EOF

  run env TT_MANIFEST_DISABLE_JQ=1 bash -c 'source "$1"; parse_stack_manifest "$2"' bash "$MANIFEST_PARSER" "$manifest_file"

  [ "$status" -eq 1 ]
  [[ "$output" == *"Unsupported stack manifest shape"* ]]

  if command -v jq >/dev/null 2>&1; then
    run bash -c 'source "$1"; parse_stack_manifest "$2"' bash "$MANIFEST_PARSER" "$manifest_file"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unsupported stack manifest shape"* ]]
  fi
}

@test "parse_stack_manifest accepts missing and empty system package pins" {
  missing_manifest="${BATS_TEST_TMPDIR}/missing-system-packages.json"
  cat >"$missing_manifest" <<'EOF'
{
  "release": "2026.05.16",
  "components": {
    "tt-kmd": "ttkmd-2.8.0",
    "tt-smi": "v5.2.0",
    "firmware": "v19.6.0",
    "tt-metal": "v0.70.1"
  }
}
EOF

  empty_manifest="${BATS_TEST_TMPDIR}/empty-system-packages.json"
  cat >"$empty_manifest" <<'EOF'
{
  "release": "2026.05.16",
  "components": {
    "tt-kmd": "ttkmd-2.8.0",
    "tt-smi": "v5.2.0",
    "firmware": "v19.6.0",
    "tt-metal": "v0.70.1"
  },
  "system_packages": {
  }
}
EOF

  run env TT_MANIFEST_DISABLE_JQ=1 bash -c '
    source "$1"
    parse_stack_manifest "$2"
    printf "%s\n" "${#TT_STACK_SYSTEM_PACKAGES[@]}"
    parse_stack_manifest "$3"
    printf "%s\n" "${#TT_STACK_SYSTEM_PACKAGES[@]}"
  ' bash "$MANIFEST_PARSER" "$missing_manifest" "$empty_manifest"

  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "0" ]
  [ "${lines[1]}" = "0" ]
}

@test "parse_stack_manifest accepts system package keys that start with digits" {
  manifest_file="${BATS_TEST_TMPDIR}/numeric-system-package-key.json"
  cat >"$manifest_file" <<'EOF'
{
  "release": "2026.05.16",
  "components": {
    "tt-kmd": "ttkmd-2.8.0",
    "tt-smi": "v5.2.0",
    "firmware": "v19.6.0",
    "tt-metal": "v0.70.1"
  },
  "system_packages": {
    "7zip": "24.09"
  }
}
EOF

  run env TT_MANIFEST_DISABLE_JQ=1 bash -c '
    source "$1"
    parse_stack_manifest "$2"
    printf "%s\n" "${TT_STACK_SYSTEM_PACKAGES[7zip]}"
  ' bash "$MANIFEST_PARSER" "$manifest_file"

  [ "$status" -eq 0 ]
  [ "$output" = "24.09" ]

  if command -v jq >/dev/null 2>&1; then
    run bash -c '
      source "$1"
      parse_stack_manifest "$2"
      printf "%s\n" "${TT_STACK_SYSTEM_PACKAGES[7zip]}"
    ' bash "$MANIFEST_PARSER" "$manifest_file"
    [ "$status" -eq 0 ]
    [ "$output" = "24.09" ]
  fi
}

@test "parse_stack_manifest fallback accepts string values with brackets and spaces" {
  manifest_file="${BATS_TEST_TMPDIR}/metadata.json"
  cat >"$manifest_file" <<'EOF'
{
  "release": "2026.05.16 beta",
  "description": "[preview] Tenstorrent Stable Stack",
  "components": {
    "tt-kmd": "ttkmd-2.8.0",
    "tt-smi": "v5.2.0",
    "firmware": "[v19.6.0 beta]",
    "tt-metal": "v0.70.1"
  }
}
EOF

  run env TT_MANIFEST_DISABLE_JQ=1 bash -c '
    source "$1"
    parse_stack_manifest "$2"
    printf "%s\n" "$TT_STACK_RELEASE"
    printf "%s\n" "$TT_STACK_DESCRIPTION"
    printf "%s\n" "${TT_STACK_COMPONENTS[firmware]}"
  ' bash "$MANIFEST_PARSER" "$manifest_file"

  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "2026.05.16 beta" ]
  [ "${lines[1]}" = "[preview] Tenstorrent Stable Stack" ]
  [ "${lines[2]}" = "[v19.6.0 beta]" ]
}
