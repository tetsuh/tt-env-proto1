# Install command quickstart

`tt-env install <release>` installs one Tenstorrent stack release under
`${TT_HOME}/versions/<release>`. If `TT_HOME` is unset, `tt-env` uses
`${HOME}/.tt-env`.

Proto1 targets Ubuntu 22.04 and Ubuntu 24.04. Linux Mint 22.1 is included as an
unofficial Ubuntu 24.04-compatible target and still needs real-host validation
before relying on KMD or hardware-level behavior. Fedora-family manifests are
fixture-only until manual validation exists.

## Prerequisites

- Bash and coreutils.
- `sudo`, `apt-get`, `curl`, and `gpg` for Ubuntu and Linux Mint system package
  manifests that use the official Tenstorrent apt repository. Custom apt
  repositories still require `add-apt-repository`, provided by
  `software-properties-common`.
- `sudo`, `dnf`, and `dnf config-manager` for dnf fixture/adapter validation.
  `config-manager` is provided by `dnf-plugins-core` on Fedora-family systems.
- `python3` with the standard `venv` module for release-local Python package
  environments.
- `curl` plus `sha256sum` or `shasum` for the GitHub Releases download fallback.
- A stack manifest in `releases/<release>.json`.
- An OS manifest for the detected host, such as `manifests/ubuntu-22.04.env`.

Install `tt-env` itself with:

```bash
bash install.sh
export PATH="${HOME}/.tt-env/shims:${HOME}/.tt-env/bin:${PATH}"
tt-env --version
```

See [PATH setup](./path-setup.md) for bash, zsh, and fish snippets. The
`${HOME}/.tt-env/shims` entry exposes commands such as `tt-smi`, while
`${HOME}/.tt-env/bin` exposes the `tt-env` CLI itself.

## Install a release

```bash
tt-env install 2026.05.16
```

The repository Ubuntu and Linux Mint manifests use the official signed
Tenstorrent apt repository at `https://ppa.tenstorrent.com/ubuntu/`. `tt-env`
adds the repository with a scoped `signed-by` keyring and installs the KMD
package as `tenstorrent-dkms`:

```text
[INFO] Adding apt repository: https://ppa.tenstorrent.com/ubuntu/
[INFO] Updating apt package metadata.
[INFO] Installing apt packages: cmake ninja-build zlib1g-dev tenstorrent-dkms
```

The official repository currently publishes Ubuntu `jammy` and `noble`
pockets. Linux Mint 22.1 uses `UBUNTU_CODENAME=noble`; unsupported or unknown
codenames fail before `tt-env` writes an apt source entry.

When a manifest has `USE_SYSTEM_PACKAGES="false"` (or legacy `USE_PPA="false"`)
and the stack manifest includes `components.<name>.download_url` plus
`components.<name>.sha256`, `tt-env` downloads each artifact and verifies its
sha256 before finalizing the version directory. Proto1-managed detached GPG
signatures are temporarily suspended for this path.

When a custom OS manifest has `USE_SYSTEM_PACKAGES="true"`, `tt-env` adds any
configured repositories before installing resolved packages. For custom apt
repositories other than the official Tenstorrent repository, `tt-env` uses
`add-apt-repository`.

Python package pins from the stack manifest are installed into a release-local
virtualenv at `${TT_HOME}/versions/<release>/venv`. `tt-env` prefers command
entrypoints from that virtualenv, such as `venv/bin/tt-smi`, and falls back to a
wrapper around system-package commands when no virtualenv entrypoint exists.

See [package manager adapter contract](./package-manager-adapters.md) for
manifest fields, adapter responsibilities, and validation requirements for new
distros.

## Idempotency and force

A completed install writes `${TT_HOME}/versions/<release>/.tt-env-installed`.
Running the same install again exits successfully without rerunning apt or
downloads:

```text
[INFO] Release 2026.05.16 is already installed at /home/alice/.tt-env/versions/2026.05.16.
```

Use `--force` to reinstall from scratch:

```bash
tt-env install --force 2026.05.16
```

Use `--dry-run` to print planned apt or download actions without creating the
version directory:

```bash
tt-env install --dry-run 2026.05.16
```

## Rollback behavior

Installs are staged in `${TT_HOME}/versions/.<release>.partial` and moved into
place only after all steps succeed. If apt, download, or sha256 verification
fails, `tt-env` removes the partial directory and leaves no broken version
directory. During `--force`, the previous installed version is kept until the
new install has completed successfully.

## Unmanaged Commands and Exclusions

To avoid breaking or shadowing the user's working local environments, some Tenstorrent-related optional commands are explicitly excluded from `tt-env` management:

- **`tt-inference-server` and `tt-studio`**: These are installed locally under `${HOME}/.local/lib/` as cloned git repositories with wrapper scripts in `${HOME}/.local/bin/` running them in Python virtual environments. They cannot be pinned or resolved as apt/pip packages, and are bypassed in shim generation to prevent active release shims from shadowing and breaking them.
- **`tt-metalium-models`**: This is a wrapper script using Podman that launches an OCI container runtime (`ghcr.io/tenstorrent/tt-metal/tt-metalium-ubuntu-22.04-release-models-amd64`). It is kept as a user-local script and not managed by `tt-env`.

If `tt-env` has no active release or does not manage a command, no shim is written, allowing the shell to fall through to any user-local scripts in `${HOME}/.local/bin/`.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `sudo is required to install <manager> packages` | Install or enable `sudo`, or use a manifest with `USE_SYSTEM_PACKAGES="false"` and component download URLs. Applies to apt and dnf system package paths. |
| `add-apt-repository is required to add repositories` | Install `software-properties-common`. |
| `Unsupported Tenstorrent apt repository codename` | Use Ubuntu 22.04/24.04 or a derivative that exposes `UBUNTU_CODENAME=jammy` or `noble`; unsupported codenames fail before apt source mutation. |
| `Tenstorrent apt signing key fingerprint mismatch` | Do not continue; check whether Tenstorrent rotated the repository signing key and update `tt-env` only after verifying the new fingerprint. |
| `Stack component <name> requires download_url and sha256` | The OS manifest disabled system packages, but the stack manifest only contains version strings. Add download URLs with sha256 metadata or use a verified package source. |
| `dnf config-manager is required to add repositories` | Install `dnf-plugins-core` before using a dnf manifest with repositories. |
| `python3 is required to create a virtualenv` | Install Python 3 and its venv support package, such as `python3-venv` on Ubuntu. |
| `curl is required to download release artifacts` | Install `curl` before using the fallback path. |
| `sha256 mismatch` | Check the stack manifest `sha256` values and artifact URLs; the partial install is rolled back. |
| `Version directory exists but is not marked installed` | Inspect the directory and rerun with `--force` if it is safe to recreate. |
