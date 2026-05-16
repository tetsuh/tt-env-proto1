# Changelog

## Unreleased

- Renamed the sample stack release from `2024.1` to `proto-stack-2026.05.16` and refreshed its component versions to the latest Tenstorrent releases observed on 2026-05-16 JST.
- Replaced the placeholder Tenstorrent Launchpad PPA with the official signed `ppa.tenstorrent.com` apt repository for Ubuntu and Linux Mint manifests, and updated the KMD package mapping to `tenstorrent-dkms`.

## 0.2.0

Proto1 v0.2.0 expands the post-v0.1.0 prototype with hosted CI, Ubuntu
24.04 coverage, package-manager adapters, and unofficial Linux Mint 22.1
compatibility.

### Phase 11 - CI & Release Hygiene

- Added GitHub Actions CI for lint and Bats on pull requests and `main`.
- Updated the CI checkout action to a Node.js 24 runtime release.

### Phase 12 - Multi-distro Groundwork

- Added an Ubuntu 24.04 OS manifest for multi-distro groundwork.
- Added Ubuntu 24.04 OS detection and manifest lookup test coverage.
- Expanded the hosted CI lint and Bats matrix to Ubuntu 22.04 and 24.04 containers.
- Documented Ubuntu 22.04 and 24.04 support boundaries.

### Phase 13 - Package Manager Abstraction

- Extracted install package manager operations behind an adapter dispatcher.
- Added a dnf package manager adapter for future Fedora manifests.
- Added an experimental Fedora 40 dnf manifest fixture for adapter coverage.
- Added `USE_SYSTEM_PACKAGES` as a neutral install-manifest flag while preserving `USE_PPA`.
- Documented package manager adapter and distro manifest contracts.

### Phase 14 - Linux Mint Compatibility

- Added an unofficial Linux Mint 22.1 compatibility manifest with detection and lookup coverage.
- Documented Linux Mint 22.1 as an Ubuntu 24.04-compatible target that still requires manual real-host validation before relying on KMD or hardware behavior.

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
