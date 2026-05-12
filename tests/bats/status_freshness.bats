#!/usr/bin/env bats

setup() {
  TT_ENV="${BATS_TEST_DIRNAME}/../../bin/tt-env"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export TT_HOME="${BATS_TEST_TMPDIR}/tt-home"
  export TT_STATUS_LSPCI_FIXTURE="${BATS_TEST_TMPDIR}/lspci-empty.txt"
  export TT_STATUS_NOW_EPOCH=1700000000
  unset GITHUB_TOKEN
  unset GH_TOKEN
}

make_fake_status_freshness_tools() {
  local fake_bin="${BATS_TEST_TMPDIR}/fake-status-freshness-bin"

  mkdir -p "$fake_bin"
  cat >"${fake_bin}/lspci" <<'EOF'
#!/usr/bin/env bash
cat "${TT_STATUS_LSPCI_FIXTURE}"
EOF
  cat >"${fake_bin}/modinfo" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  cat >"${fake_bin}/gh" <<'EOF'
#!/bin/sh
exit 1
EOF
  chmod +x "${fake_bin}/lspci" "${fake_bin}/modinfo" "${fake_bin}/gh"
  printf '%s\n' "$fake_bin"
}

@test "tt-env status prints never when manifest update marker is missing" {
  fake_bin="$(make_fake_status_freshness_tools)"
  printf '%s\n' "" >"$TT_STATUS_LSPCI_FIXTURE"

  PATH="${fake_bin}:${PATH}" run "$TT_ENV" status

  [ "$status" -eq 0 ]
  [[ "$output" == *"Manifest freshness: (never)"* ]]
}

@test "tt-env status prints manifest update age in minutes" {
  fake_bin="$(make_fake_status_freshness_tools)"
  mkdir -p "${TT_HOME}/manifests"
  printf '%s\n' "1699999700" >"${TT_HOME}/manifests/last_update"
  printf '%s\n' "" >"$TT_STATUS_LSPCI_FIXTURE"

  PATH="${fake_bin}:${PATH}" run "$TT_ENV" status

  [ "$status" -eq 0 ]
  [[ "$output" == *"Manifest freshness: 5 minutes ago"* ]]
}

@test "tt-env status prints manifest update age in hours" {
  fake_bin="$(make_fake_status_freshness_tools)"
  mkdir -p "${TT_HOME}/manifests"
  printf '%s\n' "1699992800" >"${TT_HOME}/manifests/last_update"
  printf '%s\n' "" >"$TT_STATUS_LSPCI_FIXTURE"

  PATH="${fake_bin}:${PATH}" run "$TT_ENV" status

  [ "$status" -eq 0 ]
  [[ "$output" == *"Manifest freshness: 2 hours ago"* ]]
}

@test "tt-env status prints manifest update age in days" {
  fake_bin="$(make_fake_status_freshness_tools)"
  mkdir -p "${TT_HOME}/manifests"
  printf '%s\n' "1699740800" >"${TT_HOME}/manifests/last_update"
  printf '%s\n' "" >"$TT_STATUS_LSPCI_FIXTURE"

  PATH="${fake_bin}:${PATH}" run "$TT_ENV" status

  [ "$status" -eq 0 ]
  [[ "$output" == *"Manifest freshness: 3 days ago"* ]]
}

@test "tt-env status reads manifest marker without trailing newline" {
  fake_bin="$(make_fake_status_freshness_tools)"
  mkdir -p "${TT_HOME}/manifests"
  printf '1699999700' >"${TT_HOME}/manifests/last_update"
  printf '%s\n' "" >"$TT_STATUS_LSPCI_FIXTURE"

  PATH="${fake_bin}:${PATH}" run "$TT_ENV" status

  [ "$status" -eq 0 ]
  [[ "$output" == *"Manifest freshness: 5 minutes ago"* ]]
}

@test "tt-env status prints unknown when manifest update marker is invalid" {
  fake_bin="$(make_fake_status_freshness_tools)"
  mkdir -p "${TT_HOME}/manifests"
  printf '%s\n' "invalid" >"${TT_HOME}/manifests/last_update"
  printf '%s\n' "" >"$TT_STATUS_LSPCI_FIXTURE"

  PATH="${fake_bin}:${PATH}" run "$TT_ENV" status

  [ "$status" -eq 0 ]
  [[ "$output" == *"Manifest freshness: (unknown)"* ]]
}
