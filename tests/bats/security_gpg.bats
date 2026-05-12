#!/usr/bin/env bats

setup() {
  REPO_DIR="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export TT_HOME="${BATS_TEST_TMPDIR}/tt-home"
  EXPECTED_TRUSTED_KEY_FINGERPRINT="C55FEB196FB67D83F63FE18CBEF418235C011DF8"
}

@test "bootstrap_trusted_key imports expected primary fingerprint" {
  run bash -c 'source "$1/lib/security.sh"; bootstrap_trusted_key "$TT_HOME/keys"' _ "$REPO_DIR"
  [ "$status" -eq 0 ]

  run gpg --batch --no-tty --homedir "${TT_HOME}/keys" \
    --with-colons --fingerprint "${EXPECTED_TRUSTED_KEY_FINGERPRINT}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"fpr:::::::::${EXPECTED_TRUSTED_KEY_FINGERPRINT}:"* ]]
}

@test "bootstrap_trusted_key fails when imported fingerprint is unexpected" {
  unexpected_fingerprint="0000000000000000000000000000000000000000"

  run bash -c 'source "$1/lib/security.sh"; TT_TRUSTED_KEY_FINGERPRINT="$2"; bootstrap_trusted_key "$TT_HOME/keys"' _ "$REPO_DIR" "$unexpected_fingerprint"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Trusted key fingerprint mismatch"* ]]
}
