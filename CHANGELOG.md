# Changelog

## Unreleased

- Added GitHub Actions CI for lint and Bats on pull requests and `main`.
- Updated the CI checkout action to a Node.js 24 runtime release.
- Added an Ubuntu 24.04 OS manifest for multi-distro groundwork.
- Added Ubuntu 24.04 OS detection and manifest lookup test coverage.
- Expanded the hosted CI lint and Bats matrix to Ubuntu 22.04 and 24.04 containers.
- Documented Ubuntu 22.04 and 24.04 support boundaries.
- Extracted install package manager operations behind an adapter dispatcher.

## 0.1.0

Proto1 is the first end-to-end Bash prototype of `tt-env` for Ubuntu 22.04.
It covers install, use, list, status, manifest update, security verification,
self-update, and manual release verification.

### Phase 0 - Repository Bootstrap

- Bootstrapped repository metadata, Apache-2.0 licensing, VERSION, LF policy,
  local linting, bats-core smoke testing, and proto1 scope documentation.
- Documented the companion `tt-env-manifests-proto1` manifest repository.

### Phase 1 - CLI Skeleton & Core Library

- Added the `bin/tt-env` dispatcher, `lib/core.sh` logging/failure helpers,
  Ubuntu 22.04 OS detection, `TT_HOME` initialization, and install bootstrap.

### Phase 2 - Manifest Layer

- Added a restricted OS manifest parser that avoids sourcing manifests.
- Added virtual package resolution, stack JSON parsing with fallback support,
  schema validation, and sample Ubuntu 22.04 / 2024.1 manifests.

### Phase 3 - install Command

- Implemented per-release version directories, PPA apt installation, GitHub
  Releases fallback downloads, idempotent `--force` behavior, rollback cleanup,
  and install command documentation.

### Phase 4 - use + Shims

- Added generated command shims, active release switching through
  `~/.tt-env/current`, PATH setup documentation, and shim dispatch tests.

### Phase 5 - KMD/FW Singleton Sync

- Added Tenstorrent device holder preflight checks, DKMS install/load support,
  KMD swap rollback, Secure Boot abort behavior, and KMD safety documentation.

### Phase 6 - status Command

- Added Tenstorrent hardware detection, active release reporting, KMD module
  version reporting, and manifest freshness reporting.

### Phase 7 - list / update

- Added local release listing, authenticated manifest fetching, manifest refresh
  caching, and configurable manifest mirrors.

### Phase 8 - Security

- Bootstrapped the trusted GPG key, verified manifest and binary signatures,
  enforced sha256 checks, restricted manifest workarounds to an allowlist, and
  added tests that assert the manifest parser does not invoke `source` or `.`.

### Phase 9 - Self-Update

- Added strict self-update version comparison, signed binary replacement with
  atomic `mv`, and tests showing running Bash processes survive replacement.

### Phase 10 - Hardening & 0.1.0 Release

- Added the Ubuntu 22.04 [end-to-end verification guide](./docs/e2e.md).
- Added a [manual verification checklist template](./docs/manual-verification-checklist.md)
  for pull request descriptions.
- Expanded `tt-env help <command>` with synopsis, options, examples, and exit
  codes for operator-facing command help.
