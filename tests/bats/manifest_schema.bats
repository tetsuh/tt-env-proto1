#!/usr/bin/env bats

setup() {
  MANIFEST_PARSER="${BATS_TEST_DIRNAME}/../../lib/manifest_parser.sh"
  source "$MANIFEST_PARSER"
}

parser_modes() {
  printf '%s\n' fallback
  if command -v jq >/dev/null 2>&1; then
    printf '%s\n' jq
  fi
}

run_parse_stack_manifest() {
  local mode="$1"
  local manifest_file="$2"

  if [[ "$mode" == "jq" ]]; then
    run bash -c 'source "$1"; parse_stack_manifest "$2"' bash "$MANIFEST_PARSER" "$manifest_file"
  else
    run env TT_MANIFEST_DISABLE_JQ=1 bash -c 'source "$1"; parse_stack_manifest "$2"' bash "$MANIFEST_PARSER" "$manifest_file"
  fi
}

write_stack_manifest() {
  local manifest_file="$1"
  local omitted_key="${2:-}"

  {
    printf '{\n'
    if [[ "$omitted_key" != "release" ]]; then
      printf '  "release": "proto-stack-2026.05.16",\n'
    fi
    printf '  "description": "Tenstorrent proto sample stack 2026.05.16",\n'
    printf '  "components": {\n'

    local first=1
    local key
    for key in "${TT_REQUIRED_STACK_COMPONENTS[@]}"; do
      if [[ "$omitted_key" == "components.${key}" ]]; then
        continue
      fi

      if [[ "$first" -eq 0 ]]; then
        printf ',\n'
      fi
      first=0

      case "$key" in
        tt-kmd)
          printf '    "tt-kmd": "ttkmd-2.8.0"'
          ;;
        tt-smi)
          printf '    "tt-smi": "v5.2.0"'
          ;;
        firmware)
          printf '    "firmware": "v19.6.0"'
          ;;
        tt-metal)
          printf '    "tt-metal": "v0.70.1"'
          ;;
        *)
          printf '    "%s": "v1.0.0"' "$key"
          ;;
      esac
    done

    printf '\n  }\n'
    printf '}\n'
  } >"$manifest_file"
}

@test "validate_stack_manifest accepts required keys" {
  manifest_file="${BATS_TEST_TMPDIR}/valid.json"
  write_stack_manifest "$manifest_file"

  while IFS= read -r mode; do
    run_parse_stack_manifest "$mode" "$manifest_file"
    [ "$status" -eq 0 ]
  done < <(parser_modes)
}

@test "validate_stack_manifest reports missing release" {
  manifest_file="${BATS_TEST_TMPDIR}/missing-release.json"
  write_stack_manifest "$manifest_file" "release"

  while IFS= read -r mode; do
    run_parse_stack_manifest "$mode" "$manifest_file"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Missing required stack manifest key: release"* ]]
  done < <(parser_modes)
}

@test "validate_stack_manifest reports each missing component key" {
  local component
  local missing_key

  for component in "${TT_REQUIRED_STACK_COMPONENTS[@]}"; do
    missing_key="components.${component}"
    manifest_file="${BATS_TEST_TMPDIR}/${missing_key}.json"
    write_stack_manifest "$manifest_file" "$missing_key"

    while IFS= read -r mode; do
      run_parse_stack_manifest "$mode" "$manifest_file"
      [ "$status" -eq 1 ]
      [[ "$output" == *"Missing required stack manifest key: ${missing_key}"* ]]
    done < <(parser_modes)
  done
}
