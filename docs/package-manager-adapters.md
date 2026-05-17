# Package manager adapter contract

This document defines the proto1 contract for OS manifests and package manager
adapters. It is intended for future distro work and does not by itself expand
the supported OS list.

## Install flow

`tt-env install` detects the host OS, loads `manifests/<id>-<version>.env`, and
parses it without sourcing it. When system package installation is enabled, the
install path dispatches to the adapter named by `PKG_MANAGER`.

System package installation is controlled by:

1. `USE_SYSTEM_PACKAGES`, the distro-neutral flag for new manifests.
2. `USE_PPA`, the legacy Ubuntu-compatible fallback.

If the selected flag is `false`, `tt-env` skips package-manager operations and
uses component downloads plus manifest-provided sha256 checksums instead.

## OS manifest fields

| Field | Required | Meaning |
| --- | --- | --- |
| `PKG_MANAGER` | Yes | Adapter name. Currently `apt` and `dnf` are implemented. |
| `USE_SYSTEM_PACKAGES` | New manifests | `true` to install system packages through the adapter, `false` to use checksum-verified downloads. |
| `USE_PPA` | Legacy Ubuntu manifests | Backward-compatible alias for `USE_SYSTEM_PACKAGES`. Avoid it for non-Ubuntu manifests. |
| `REQUIRED_REPOS` | Yes | Array of repositories the adapter must configure before package install. Use `()` when none are needed. |
| `VIRT_PKG_<NAME>` | Yes | Native package name for each virtual dependency (`cmake`, `ninja`, `zlib`, `kmd`, `smi`, `flash`, `topology`). |
| `WORKAROUNDS` | Yes | Allowlisted workaround keys. Use `()` when none are needed. |

Virtual package names are normalized by `resolve_package`, so `zlib` maps to
`VIRT_PKG_ZLIB`. Missing mappings must fail closed rather than falling back to a
guess.

## Adapter responsibilities

Each adapter must:

1. Resolve all virtual packages from the parsed manifest before mutating the system.
2. Make `--dry-run` side-effect free: no `sudo`, package-manager command, network, or file-system mutation.
3. Check required local tools before running privileged commands.
4. Add required repositories before refreshing package metadata.
5. Refresh package metadata before installing packages.
6. Surface failures with clear `fail` messages and never silently skip a failed step.
7. Preserve command ordering in tests so repository setup, metadata refresh, and install remain deterministic.

The current adapters behave as follows:

| Adapter | Repository setup | Metadata refresh | Install command |
| --- | --- | --- | --- |
| `apt` | `sudo add-apt-repository -y <repo>` | `sudo apt-get update` | `sudo apt-get install -y <packages...>` |
| `dnf` | `sudo dnf config-manager --add-repo <repo>` | `sudo dnf makecache` | `sudo dnf install -y <packages...>` |

For `dnf`, manifests with repositories require the `config-manager` plugin
(`dnf-plugins-core` on Fedora-family systems).

## Adding a distro or adapter

For a new package manager:

1. Add a new branch in `package_manager_install_system_packages`.
2. Implement the adapter in `lib/package_manager.sh`.
3. Add Bats coverage for dry-run output, privileged command ordering, missing tools, and unsupported-manager behavior.
4. Keep unsupported managers fail-closed.

For a new distro manifest:

1. Add a fixture first unless real manual validation already exists.
2. Use `USE_SYSTEM_PACKAGES`, not `USE_PPA`, outside Ubuntu.
3. Map every virtual package explicitly.
4. Add parser coverage and adapter integration coverage for the mapping.
5. Document whether the distro is fixture-only or manually validated.

Hosted CI and Bats coverage only prove parser and adapter behavior. A distro is
not supported until manual E2E validation has been completed on that distro,
including hardware/system-level behavior when KMD paths are involved.
