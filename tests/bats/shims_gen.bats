#!/usr/bin/env bats

setup() {
  REPO_DIR="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export TT_HOME="${BATS_TEST_TMPDIR}/tt-home"
  source "${REPO_DIR}/lib/shims.sh"
}

@test "generate_shims creates executable shims for known commands" {
  generate_shims >/dev/null

  for command_name in $(list_known_shims); do
    shim_path="${TT_HOME}/shims/${command_name}"

    [ -x "$shim_path" ]
    [[ "$(head -n 1 "$shim_path")" == "#!/usr/bin/env bash" ]]
    grep -q 'current/bin/${command_name}' "$shim_path"
  done
}

@test "generated shim dispatches through TT_HOME current by basename" {
  generate_shims >/dev/null
  mkdir -p "${TT_HOME}/current/bin"
  cat >"${TT_HOME}/current/bin/tt-smi" <<'EOF'
#!/usr/bin/env bash
printf 'mock tt-smi %s\n' "$*"
EOF
  chmod +x "${TT_HOME}/current/bin/tt-smi"

  run "${TT_HOME}/shims/tt-smi" "--json" "device0"

  [ "$status" -eq 0 ]
  [ "$output" = "mock tt-smi --json device0" ]
}
