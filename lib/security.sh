#!/usr/bin/env bash
# Security helpers for tt-env.
#
# Public symbols:
#   - calculate_sha256 <file>
#   - verify_sha256 <file> <expected-sha256>
#   - bootstrap_trusted_key [key-home]
#   - trusted_key_fingerprint
#   - verify_gpg <file> <signature-file> [key-home]

if [[ -n "${TT_SECURITY_LOADED:-}" ]]; then
    return 0
fi
TT_SECURITY_LOADED=1

SECURITY_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SECURITY_LIB_DIR}/core.sh"

TT_TRUSTED_KEY_FINGERPRINT="C55FEB196FB67D83F63FE18CBEF418235C011DF8"
TT_TRUSTED_PUBLIC_KEY_FILE="tt-env-proto-signing-key.asc"

calculate_sha256() {
    local file="$1"
    local output

    [[ -f "$file" ]] || fail "Cannot calculate sha256; file not found: ${file}"

    if command_exists sha256sum; then
        output="$(sha256sum "$file")"
        printf '%s\n' "${output%% *}"
    elif command_exists shasum; then
        output="$(shasum -a 256 "$file")"
        printf '%s\n' "${output%% *}"
    else
        fail "sha256sum or shasum is required to verify downloaded artifacts."
    fi
}

verify_sha256() {
    local file="$1"
    local expected_sha256="${2,,}"
    local actual_sha256

    actual_sha256="$(calculate_sha256 "$file")"
    actual_sha256="${actual_sha256,,}"

    if [[ "$actual_sha256" != "$expected_sha256" ]]; then
        fail "sha256 mismatch for ${file}: expected ${expected_sha256}, got ${actual_sha256}"
    fi
}

trusted_key_fingerprint() {
    printf '%s\n' "$TT_TRUSTED_KEY_FINGERPRINT"
}

_trusted_public_key() {
    cat <<'EOF'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mDMEagOU/hYJKwYBBAHaRw8BAQdAmRLwhaL9E8baFIJY7IPonrch/WBn7hnrB4rX
lBsdzqO0Q1RlbnN0b3JyZW50IHR0LWVudiBQcm90byBTaWduaW5nIEtleSA8dHQt
ZW52LXByb3RvQGV4YW1wbGUuaW52YWxpZD6IkAQTFgoAOBYhBMVf6xlvtn2D9j/h
jL70GCNcAR34BQJqA5T+AhsDBQsJCAcCBhUKCQgLAgQWAgMBAh4BAheAAAoJEL70
GCNcAR34UVUA/jahbDgxJZ0p35kyTbDz5FEjo5zTqOrF2yC6VeYB71sFAQD4xkWg
h0O5th2JRvPeHnYdQjdjKneWoz2RquNsEgUrBg==
=cvpz
-----END PGP PUBLIC KEY BLOCK-----
EOF
}

_trusted_key_primary_fingerprints() {
    local key_home="$1"

    GNUPGHOME="$key_home" gpg --batch --no-tty --homedir "$key_home" \
        --with-colons --fingerprint 2>/dev/null |
        awk -F: '
            $1 == "pub" { want = 1; next }
            want && $1 == "fpr" { print toupper($10); want = 0; next }
            $1 == "sub" || $1 == "ssb" { want = 0 }
        '
}

bootstrap_trusted_key() {
    local key_home="${1:-${TT_HOME}/keys}"
    local public_key_file="${key_home}/${TT_TRUSTED_PUBLIC_KEY_FILE}"
    local public_key_tmp="${public_key_file}.tmp.$$"
    local old_umask

    command_exists gpg || fail "gpg is required to bootstrap the tt-env trusted public key."

    old_umask="$(umask)"
    umask 077
    mkdir -p "$key_home" || fail "Failed to create trusted key directory: ${key_home}"
    chmod 700 "$key_home" || fail "Failed to secure trusted key directory: ${key_home}"
    _trusted_public_key >"$public_key_tmp" || fail "Failed to write trusted public key: ${public_key_tmp}"
    mv "$public_key_tmp" "$public_key_file" || fail "Failed to install trusted public key: ${public_key_file}"
    umask "$old_umask"

    GNUPGHOME="$key_home" gpg --batch --no-tty --quiet --homedir "$key_home" \
        --import "$public_key_file" >/dev/null ||
        fail "Failed to import tt-env trusted public key into ${key_home}"

    if ! _trusted_key_primary_fingerprints "$key_home" | grep -Fxq "$TT_TRUSTED_KEY_FINGERPRINT"; then
        fail "Trusted key fingerprint mismatch in ${key_home}; expected ${TT_TRUSTED_KEY_FINGERPRINT}"
    fi
}

verify_gpg() {
    local file="$1"
    local signature_file="$2"
    local key_home="${3:-${TT_HOME}/keys}"
    local status_output

    command_exists gpg || fail "gpg is required to verify GPG signatures."
    [[ -f "$file" ]] || fail "Cannot verify GPG signature; file not found: ${file}"
    [[ -f "$signature_file" ]] || fail "Missing GPG signature for ${file}: ${signature_file}"

    if ! _trusted_key_primary_fingerprints "$key_home" | grep -Fxq "$TT_TRUSTED_KEY_FINGERPRINT"; then
        bootstrap_trusted_key "$key_home"
    fi

    if ! status_output="$(GNUPGHOME="$key_home" gpg --batch --no-tty --status-fd 1 \
        --homedir "$key_home" --verify "$signature_file" "$file" 2>&1)"; then
        fail "GPG signature verification failed for ${file}"
    fi

    if ! awk -v expected="$TT_TRUSTED_KEY_FINGERPRINT" '
        $1 == "[GNUPG:]" && ($2 == "BADSIG" || $2 == "ERRSIG" || $2 == "EXPKEYSIG" || $2 == "REVKEYSIG") {
            bad = 1
        }
        $1 == "[GNUPG:]" && $2 == "VALIDSIG" {
            signer = toupper($3)
            primary = toupper($NF)
            if (signer == expected || primary == expected) {
                valid = 1
            }
        }
        END {
            if (bad) {
                exit 2
            }
            exit valid ? 0 : 1
        }
    ' <<<"$status_output"; then
        fail "GPG signature for ${file} was not made by trusted key ${TT_TRUSTED_KEY_FINGERPRINT}"
    fi
}
