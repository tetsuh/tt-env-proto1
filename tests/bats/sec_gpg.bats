#!/usr/bin/env bats

setup() {
  REPO_DIR="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export TT_HOME="${BATS_TEST_TMPDIR}/tt-home"
}

write_signed_fixture_script() {
  local script_file="$1"

  cat >"$script_file" <<'EOF'
set -euo pipefail
source "$1/lib/security.sh"

work_dir="$2"
sign_home="${work_dir}/sign-home"
key_home="${work_dir}/key-home"
payload="${work_dir}/payload"
signature="${work_dir}/payload.asc"
public_key="${work_dir}/public.asc"

mkdir -p "$sign_home" "$key_home"
chmod 700 "$sign_home" "$key_home"
gpg --batch --homedir "$sign_home" --pinentry-mode loopback --passphrase "" \
  --quick-generate-key "tt-env test signing key <test@example.invalid>" ed25519 sign 0 >/dev/null
fingerprint="$(gpg --batch --homedir "$sign_home" --with-colons --fingerprint "test@example.invalid" |
  awk -F: '$1 == "fpr" { print $10; exit }')"
gpg --batch --homedir "$sign_home" --armor --export "$fingerprint" >"$public_key"
printf 'trusted payload\n' >"$payload"
gpg --batch --homedir "$sign_home" --pinentry-mode loopback --passphrase "" \
  --armor --detach-sign --output "$signature" "$payload"

TT_TRUSTED_KEY_FINGERPRINT="$fingerprint"
TEST_TRUSTED_PUBLIC_KEY="$public_key"
_trusted_public_key() {
  cat "$TEST_TRUSTED_PUBLIC_KEY"
}

if [[ "${TAMPER_PAYLOAD:-0}" -eq 1 ]]; then
  printf 'tampered payload\n' >"$payload"
fi

bootstrap_trusted_key "$key_home"
verify_gpg "$payload" "$signature" "$key_home"
EOF
}

@test "verify_gpg accepts a trusted detached signature" {
  script_file="${BATS_TEST_TMPDIR}/verify-good.sh"
  write_signed_fixture_script "$script_file"

  run bash "$script_file" "$REPO_DIR" "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
}

@test "verify_gpg rejects a bad detached signature" {
  script_file="${BATS_TEST_TMPDIR}/verify-bad.sh"
  write_signed_fixture_script "$script_file"

  TAMPER_PAYLOAD=1 run bash "$script_file" "$REPO_DIR" "$BATS_TEST_TMPDIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"GPG signature verification failed"* ]]
}
