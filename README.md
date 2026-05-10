# tt-env-proto1

Prototype repository for **tt-env** — a next-generation environment manager for the Tenstorrent
software stack.

This repository hosts the **proto1** iteration: the first end-to-end working prototype written in
Bash, targeting Ubuntu 22.04, and built incrementally via Ticket Driven Development.

## Status

🚧 Work in progress. Development is tracked through the GitHub
[Issues](https://github.com/tetsuh/tt-env-proto1/issues) and
[Milestones](https://github.com/tetsuh/tt-env-proto1/milestones) of this repository
(Phase 0 → Phase 10).

## Scope of proto1

- **Language**: Bash (zero-dependency bootstrap)
- **Target OS**: Ubuntu 22.04 only
- **Install location**: `~/.tt-env/versions/<release>/` (KMD lives in the system module path)
- **Distribution**: Falls back to GitHub Releases direct download when the official PPA is not
  available
- **Stack manifests**: Sourced from the private repo `tt-env-manifests-proto1`
- **Secure Boot**: Not supported in proto1 (the tool aborts when Secure Boot is enabled)
- **CI**: Not configured for proto1 — verification is manual on real Ubuntu 22.04 hardware

## Verification Flow

Since **proto1** has no automated CI, contributors must run verification scripts locally before opening a Pull Request.

### 1. Linting

Requires `shellcheck`.
```bash
# Ubuntu 22.04
sudo apt-get install shellcheck

bash scripts/lint.sh
```

### 2. Testing

Requires `bats-core` (vendored in this repo).
```bash
bash scripts/test.sh
```

### 3. Manual Verification

Major changes (especially those touching KMD or system-level state) must be verified on real Ubuntu 22.04 hardware. Detailed verification steps are documented in the [End-to-End Verification Guide](./docs/e2e.md) (Phase 10).

## Contributing

Contributions are coordinated entirely through GitHub Issues and pull requests.
Commit messages and PR titles must follow
[Conventional Commits](https://www.conventionalcommits.org/) (e.g. `feat(cli): add status command`).

## License

Apache License 2.0 — see `LICENSE`.
