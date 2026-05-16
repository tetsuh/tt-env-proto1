# Security

## Current proto1 trust model

Proto1 temporarily suspends project-managed GPG signature enforcement for
manifests, direct-download stack artifacts, and self-update binaries. The
previous embedded proto1 public key was not a Tenstorrent official signing key,
and the matching private key is not under an operational key-management process.
Keeping that signature requirement would imply a stronger authenticity guarantee
than proto1 can currently provide.

The current guarantees are:

- Official Tenstorrent apt repository setup verifies the repository signing key
  fingerprint before writing apt sources.
- Direct-download stack artifacts still require manifest-provided sha256
  checksums, and checksum mismatches abort before a release is marked installed.
- Manifest updates require HTTPS transport and a valid archive shape, but do not
  currently authenticate manifest publisher identity with proto1-managed GPG.
- `tt-env update --self` requires HTTPS transport, but does not currently verify
  a proto1-managed detached signature.

This means proto1 currently protects artifact integrity when checksums are
available, but it does not provide project-managed GPG authenticity or downgrade
protection for manifests. Reintroduce GPG only after a clear trust model exists,
such as verified upstream Tenstorrent signatures or a managed project signing key
with documented private-key custody.

Existing `${TT_HOME}/keys` directories from older proto1 installs are legacy
state and are no longer used by default.
