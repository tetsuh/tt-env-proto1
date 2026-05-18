# tt-env-manifests-proto1

This is the companion private repository for **tt-env-proto1**, containing the software stack and OS manifests.

## Repository URL

[https://github.com/tetsuh/tt-env-manifests-proto1](https://github.com/tetsuh/tt-env-manifests-proto1)

## Layout

```
tt-env-manifests-proto1/
├── README.md
├── LICENSE
├── releases/
│   └── 2026.05.16.json           # Stack manifest for release 2026.05.16
└── manifests/
    └── ubuntu-22.04.env      # OS manifest for Ubuntu 22.04
```

## Authentication

Since this is a private repository, **tt-env** requires authentication to fetch manifests during `tt-env update` (Phase 7).

The tool will prioritize:
1. `GITHUB_TOKEN` environment variable.
2. `GH_TOKEN` environment variable.
3. The `gh` CLI credentials (if `gh` is installed and authenticated).

## Mirrors

`tt-env update` reads optional mirror repositories from `~/.tt-env/config` before falling back to the default manifest repository.

```sh
MIRRORS=(
  "example/tt-env-manifests-mirror"
  "another-org/tt-env-manifests"
)
```

Mirrors use the same archive layout as `tt-env-manifests-proto1` and are tried in order. The first successful source wins.

## Contribution

Updates to manifests should be made directly in the `tt-env-manifests-proto1` repository.
Major schema changes should be coordinated with the core `tt-env` tool development by opening an Issue in the [tt-env-proto1](https://github.com/tetsuh/tt-env-proto1/issues) repository.

Stack manifests may include a `system_packages` object for best-effort package
manager version pins. Keys are virtual package names resolved through the OS
manifest (`kmd` maps to `VIRT_PKG_KMD`, `smi` maps to `VIRT_PKG_SMI`, and so
on), not distro-specific package names:

```json
{
  "system_packages": {
    "kmd": "2.8.0",
    "smi": "5.0.1",
    "flash": "3.6.5",
    "topology": "1.2.19"
  }
}
```

These pins are intended for comparing dated stack releases such as
`2026.05.16` and `2026.08.16`. They rely on upstream package repositories
retaining historical package versions; `tt-env` does not mirror or archive
those packages.

The `components` object records stack component versions or downloadable
artifacts. The `system_packages` object records distro package versions used to
install system-managed tools for a release. They are related but distinct
metadata and may use different version formats.

Stack manifests may also include a `python_packages` object for release-local
pip dependencies that supplement upstream system packages:

```json
{
  "python_packages": {
    "tt-umd": "0.9.5",
    "textual": "0.59.0",
    "elasticsearch": "8.11.0"
  }
}
```

Python package names must use alphanumeric characters plus `.`, `_`, or `-`.
System package keys must use lowercase alphanumeric characters plus `_`.
Versions must be pinned. Python package versions may use alphanumeric
characters plus `.`, `_`, `!`, `+`, or `-`. System package versions may also
use `:` and `~` for apt/dnf-style version strings.
