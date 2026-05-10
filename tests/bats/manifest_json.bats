#!/usr/bin/env bats

setup() {
  MANIFEST_PARSER="${BATS_TEST_DIRNAME}/../../lib/manifest_parser.sh"
}

write_stack_manifest() {
  local manifest_file="$1"
  cat >"$manifest_file" <<'EOF'
{
  "release": "2024.1",
  "description": "Tenstorrent Stable Stack 2024.1",
  "components": {
    "tt-kmd": "v2.5.0",
    "tt-smi": "v3.0.38",
    "firmware": "19.2.0",
    "tt-metal": "v0.65.0"
  }
}
EOF
}

@test "parse_stack_manifest fallback extracts release metadata and components" {
  manifest_file="${BATS_TEST_TMPDIR}/2024.1.json"
  write_stack_manifest "$manifest_file"

  run env TT_MANIFEST_DISABLE_JQ=1 bash -c '
    source "$1"
    parse_stack_manifest "$2"
    printf "%s\n" "$TT_STACK_RELEASE"
    printf "%s\n" "$TT_STACK_DESCRIPTION"
    printf "%s\n" "${TT_STACK_COMPONENTS[tt-kmd]}"
    printf "%s\n" "${TT_STACK_COMPONENTS[tt-metal]}"
  ' bash "$MANIFEST_PARSER" "$manifest_file"

  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "2024.1" ]
  [ "${lines[1]}" = "Tenstorrent Stable Stack 2024.1" ]
  [ "${lines[2]}" = "v2.5.0" ]
  [ "${lines[3]}" = "v0.65.0" ]
}

@test "parse_stack_manifest jq and fallback paths return identical results" {
  command -v jq >/dev/null 2>&1 || skip "jq not available"

  manifest_file="${BATS_TEST_TMPDIR}/2024.1.json"
  write_stack_manifest "$manifest_file"

  run bash -c '
    source "$1"
    parse_stack_manifest "$2"
    printf "%s|%s|%s|%s|%s|%s\n" \
      "$TT_STACK_RELEASE" \
      "$TT_STACK_DESCRIPTION" \
      "${TT_STACK_COMPONENTS[tt-kmd]}" \
      "${TT_STACK_COMPONENTS[tt-smi]}" \
      "${TT_STACK_COMPONENTS[firmware]}" \
      "${TT_STACK_COMPONENTS[tt-metal]}"
  ' bash "$MANIFEST_PARSER" "$manifest_file"
  [ "$status" -eq 0 ]
  jq_output="$output"

  run env TT_MANIFEST_DISABLE_JQ=1 bash -c '
    source "$1"
    parse_stack_manifest "$2"
    printf "%s|%s|%s|%s|%s|%s\n" \
      "$TT_STACK_RELEASE" \
      "$TT_STACK_DESCRIPTION" \
      "${TT_STACK_COMPONENTS[tt-kmd]}" \
      "${TT_STACK_COMPONENTS[tt-smi]}" \
      "${TT_STACK_COMPONENTS[firmware]}" \
      "${TT_STACK_COMPONENTS[tt-metal]}"
  ' bash "$MANIFEST_PARSER" "$manifest_file"
  [ "$status" -eq 0 ]
  [ "$output" = "$jq_output" ]
}

@test "parse_stack_manifest fallback rejects unknown JSON shapes" {
  manifest_file="${BATS_TEST_TMPDIR}/bad.json"
  cat >"$manifest_file" <<'EOF'
{
  "release": "2024.1",
  "components": []
}
EOF

  run env TT_MANIFEST_DISABLE_JQ=1 bash -c 'source "$1"; parse_stack_manifest "$2"' bash "$MANIFEST_PARSER" "$manifest_file"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unsupported stack manifest shape"* ]]
}

@test "parse_stack_manifest fallback accepts string values with brackets and spaces" {
  manifest_file="${BATS_TEST_TMPDIR}/metadata.json"
  cat >"$manifest_file" <<'EOF'
{
  "release": "2024.1 beta",
  "description": "[preview] Tenstorrent Stable Stack",
  "components": {
    "firmware": "[19.2.0 beta]"
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
  [ "${lines[0]}" = "2024.1 beta" ]
  [ "${lines[1]}" = "[preview] Tenstorrent Stable Stack" ]
  [ "${lines[2]}" = "[19.2.0 beta]" ]
}
