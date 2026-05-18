#!/usr/bin/env bats

setup() {
  TT_ENV="${BATS_TEST_DIRNAME}/../../bin/tt-env"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export TT_HOME="${BATS_TEST_TMPDIR}/tt-home"
  mkdir -p "${TT_HOME}/releases"
}

write_release_manifest() {
  local release="$1"
  local metal="$2"
  local kmd="$3"
  local umd="$4"

  cat >"${TT_HOME}/releases/${release}.json" <<EOF
{
  "release": "${release}",
  "components": {
    "tt-kmd": "ttkmd-${kmd}",
    "tt-smi": "v5.2.0",
    "firmware": "v19.6.0",
    "tt-metal": "${metal}"
  },
  "system_packages": {
    "kmd": "${kmd}",
    "smi": "5.0.1",
    "flash": "3.6.5",
    "topology": "1.2.19"
  },
  "python_packages": {
    "tt-umd": "${umd}",
    "textual": "0.59.0",
    "elasticsearch": "8.11.0"
  }
}
EOF
}

@test "tt-env diff compares components system packages and python packages" {
  write_release_manifest 2026.05.16 v0.70.1 2.8.0 0.9.5
  write_release_manifest 2026.08.16 v0.76.0 3.1.0 1.2.0

  run "$TT_ENV" diff 2026.05.16 2026.08.16

  [ "$status" -eq 0 ]
  [[ "$output" == *"Item"* ]]
  [[ "$output" == *"2026.05.16"* ]]
  [[ "$output" == *"2026.08.16"* ]]
  [[ "$output" == *"components.tt-metal"*v0.70.1*v0.76.0* ]]
  [[ "$output" == *"system_packages.kmd"*2.8.0*3.1.0* ]]
  [[ "$output" == *"python_packages.tt-umd"*0.9.5*1.2.0* ]]
}

@test "tt-env diff marks missing values" {
  write_release_manifest 2026.05.16 v0.70.1 2.8.0 0.9.5
  write_release_manifest 2026.08.16 v0.76.0 3.1.0 1.2.0
  tmp_file="${TT_HOME}/releases/2026.08.16.json"
  python3 - "$tmp_file" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
del data["python_packages"]["textual"]
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY

  run "$TT_ENV" diff 2026.05.16 2026.08.16

  [ "$status" -eq 0 ]
  [[ "$output" == *"python_packages.textual"*0.59.0*" -"* ]]
}

@test "tt-env diff fails for unknown releases" {
  write_release_manifest 2026.05.16 v0.70.1 2.8.0 0.9.5

  run "$TT_ENV" diff 2026.05.16 2026.08.16

  [ "$status" -eq 1 ]
  [[ "$output" == *"Release manifest not found for 2026.08.16"* ]]
}

@test "tt-env diff requires two release arguments" {
  run "$TT_ENV" diff 2026.05.16

  [ "$status" -eq 1 ]
  [[ "$output" == *"tt-env diff <release-a> <release-b>"* ]]
}
