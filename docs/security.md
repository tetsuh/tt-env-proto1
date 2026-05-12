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

This is the proto1 project signing key used to verify manifest and binary
artifact signatures.

Downloaded binary artifacts must provide a detached ASCII-armored signature next
to the artifact URL using the `.asc` suffix. For example, a component downloaded
from `https://example.invalid/tt-smi` must also provide
`https://example.invalid/tt-smi.asc`.

Manifest updates verify each downloaded `releases/*.json` and `manifests/*.env`
file against its sidecar `.asc` file before replacing the local manifest cache.
Missing or invalid signatures abort before the existing cache is mutated.
