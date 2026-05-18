# tt-env-proto1

[![CI](https://github.com/tetsuh/tt-env-proto1/actions/workflows/ci.yml/badge.svg)](https://github.com/tetsuh/tt-env-proto1/actions/workflows/ci.yml)

Prototype repository for **tt-env** — a next-generation environment manager for the Tenstorrent
software stack.

This repository hosts the **proto1** iteration: the first end-to-end working prototype written in
Bash, targeting Ubuntu 22.04 and 24.04, and built incrementally via Ticket Driven Development.

## Status

🚧 Work in progress. Development is tracked through the GitHub
[Issues](https://github.com/tetsuh/tt-env-proto1/issues) and
[Milestones](https://github.com/tetsuh/tt-env-proto1/milestones) of this repository
(Phase 0 -> Phase 14).

## Scope of proto1

- **Language**: Bash (zero-dependency bootstrap)
- **Target OS**: Ubuntu 22.04 and Ubuntu 24.04; unofficial Linux Mint 22.1 compatibility
- **Install location**: `~/.tt-env/versions/<release>/` (KMD lives in the system module path)
- **Distribution**: Falls back to GitHub Releases direct download when the official PPA is not
  available
- **Stack manifests**: Sourced from the private repo `tt-env-manifests-proto1`
- **Secure Boot**: Not supported in proto1 (the tool aborts when Secure Boot is enabled)
- **CI**: GitHub Actions runs lint and Bats in Ubuntu 22.04 and 24.04
  containers; hardware E2E verification remains manual on real Ubuntu hosts

Fedora-family manifests are currently fixtures for dnf adapter development
only. They are not included in the supported OS list until real Fedora manual
verification is completed.
Linux Mint 22.1 is included as an unofficial Ubuntu 24.04-compatible target; it
still requires manual validation on real Linux Mint hosts before relying on KMD
or hardware-level behavior.

## Install quickstart

See [docs/install.md](./docs/install.md) for `tt-env install <release>` usage,
prerequisites, sudo behavior, fallback downloads, and troubleshooting.
See [docs/package-manager-adapters.md](./docs/package-manager-adapters.md)
for OS manifest fields, package manager adapter responsibilities, and distro
fixture expectations.
See [docs/path-setup.md](./docs/path-setup.md) for shell-specific PATH setup
that enables both `tt-env` and generated shims such as `tt-smi`.
See [docs/release-diff.md](./docs/release-diff.md) for comparing dated stack
release manifests with `tt-env diff`.
See [docs/kmd-safety.md](./docs/kmd-safety.md) for KMD preflight, Secure Boot,
swap, rollback, and recovery guidance.
See [docs/e2e.md](./docs/e2e.md) for the full Ubuntu manual
install -> use -> status -> update -> self-update verification flow.

## Verification Flow

GitHub Actions runs lint and Bats on pull requests and pushes to `main`.
Contributors should also run verification scripts locally before opening a pull
request so failures can be fixed before review.

### 1. Linting

Requires `shellcheck`.
```bash
bash scripts/lint.sh
```

### 2. Testing

Requires `bats-core` (vendored in this repo).
```bash
bash scripts/test.sh
```

### 3. Manual Verification

Major changes (especially those touching KMD or system-level state) must still
be verified on real Ubuntu hardware for the affected supported release.
Detailed verification steps are documented in [docs/e2e.md](./docs/e2e.md).

## Contributing

Contributions are coordinated entirely through GitHub Issues and pull requests.
Commit messages and PR titles must follow
[Conventional Commits](https://www.conventionalcommits.org/) (e.g. `feat(cli): add status command`).

## License

Apache License 2.0 — see `LICENSE`.
