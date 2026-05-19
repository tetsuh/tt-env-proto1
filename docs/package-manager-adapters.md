# Package manager adapter contract

This document defines the proto1 contract for OS manifests and package manager
adapters. It is intended for future distro work and does not by itself expand
the supported OS list.

## Install flow

`tt-env install` detects the host OS, loads `manifests/<id>-<version>.env`, and
parses it without sourcing it. It also parses the selected stack release
manifest for system package version pins. When system package installation is
enabled, the install path dispatches to the adapter named by `PKG_MANAGER`.

System package installation is controlled by:

1. `USE_SYSTEM_PACKAGES`, the distro-neutral flag for new manifests.
2. `USE_PPA`, the legacy Ubuntu-compatible fallback.

If the selected flag is `false`, `tt-env` skips package-manager operations and
uses component downloads plus manifest-provided sha256 checksums instead.

Stack manifests must pin Tenstorrent-managed system package versions under
`system_packages` when system package installation is enabled. The keys are
virtual package names, not distro-specific names:

```json
{
  "system_packages": {
    "kmd": "2.8.0",
    "smi": "5.0.1",
    "flash": "3.6.5",
    "topology": "1.2.19",
    "burnin": "0.4.0"
  }
}
```

Adapters format those pins for their native package manager. `apt` uses
`<package>=<version>`, while `dnf` uses `<package>-<version>`. If a pinned
version is no longer available in the configured repository, the native package
manager error is surfaced.

Some upstream system packages need Python dependencies that are not declared by
the native package metadata. Stack manifests pin those dependencies under
`python_packages`, and `tt-env` installs them into a release-local virtualenv at
`${TT_HOME}/versions/<release>/venv`. If pip installs a command entrypoint such
as `venv/bin/tt-smi`, `tt-env` uses that release-local entrypoint. Otherwise,
affected system-package commands use wrappers that enter the release virtualenv
and re-execute Python scripts with `venv/bin/python` so the pinned dependencies
are active at runtime.

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
3. Apply stack manifest pins for Tenstorrent-managed packages before install.
4. Check required local tools before running privileged commands.
5. Add required repositories before refreshing package metadata.
6. Refresh package metadata before installing packages.
7. Surface failures with clear `fail` messages and never silently skip a failed step.
8. Preserve command ordering in tests so repository setup, metadata refresh, and install remain deterministic.

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
