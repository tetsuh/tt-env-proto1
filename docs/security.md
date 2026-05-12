# Security

`install.sh` bootstraps the proto1 project signing public key into
`${TT_HOME}/keys` and verifies that the imported primary key fingerprint matches:

```text
C55F EB19 6FB6 7D83 F63F  E18C BEF4 1823 5C01 1DF8
```

The armored public key is stored at
`${TT_HOME}/keys/tt-env-proto-signing-key.asc`. To inspect the installed keyring:

```bash
gpg --homedir "${TT_HOME:-$HOME/.tt-env}/keys" --list-keys
```

This is the proto1 project signing key used to anchor later manifest and binary
verification work. Signature verification logic is implemented in follow-up
Phase 8 tickets.
