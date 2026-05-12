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
│   └── 2024.1.json           # Stack manifest for release 2024.1
└── manifests/
    └── ubuntu-22.04.env      # OS manifest for Ubuntu 22.04
```

## Authentication

Since this is a private repository, **tt-env** requires authentication to fetch manifests during `tt-env update` (Phase 7).

The tool will prioritize:
1. `GITHUB_TOKEN` environment variable.
2. `GH_TOKEN` environment variable.
3. The `gh` CLI credentials (if `gh` is installed and authenticated).

## Contribution

Updates to manifests should be made directly in the `tt-env-manifests-proto1` repository.
Major schema changes should be coordinated with the core `tt-env` tool development by opening an Issue in the [tt-env-proto1](https://github.com/tetsuh/tt-env-proto1/issues) repository.
