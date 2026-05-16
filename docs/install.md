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
- `sudo`, `apt-get`, and `add-apt-repository` for Ubuntu system package installs.
  `add-apt-repository` is provided by `software-properties-common`.
- `sudo`, `dnf`, and `dnf config-manager` for dnf fixture/adapter validation.
  `config-manager` is provided by `dnf-plugins-core` on Fedora-family systems.
- `curl` plus `sha256sum` or `shasum` for the GitHub Releases download fallback.
- `gpg` for bootstrapping the proto1 trusted public key into `${TT_HOME}/keys`.
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
tt-env install 2024.1
```

When the OS manifest has `USE_SYSTEM_PACKAGES="true"` (or legacy
`USE_PPA="true"` for Ubuntu), `tt-env` adds required repositories before
installing resolved packages. A successful Ubuntu apt-path run looks like:

```text
[INFO] Adding apt repository: ppa:tenstorrent/ppa
[INFO] Updating apt package metadata.
[INFO] Installing apt packages: cmake ninja-build zlib1g-dev tenstorrent-dkms
[INFO] Installed release 2024.1 at /home/alice/.tt-env/versions/2024.1.
```

When the manifest has `USE_SYSTEM_PACKAGES="false"` (or legacy
`USE_PPA="false"`), `tt-env` downloads component artifacts from
`components.<name>.download_url` in the stack manifest and verifies each artifact
against `components.<name>.sha256` before finalizing the version directory.

See [package manager adapter contract](./package-manager-adapters.md) for
manifest fields, adapter responsibilities, and validation requirements for new
distros.

## Idempotency and force

A completed install writes `${TT_HOME}/versions/<release>/.tt-env-installed`.
Running the same install again exits successfully without rerunning apt or
downloads:

```text
[INFO] Release 2024.1 is already installed at /home/alice/.tt-env/versions/2024.1.
```

Use `--force` to reinstall from scratch:

```bash
tt-env install --force 2024.1
```

Use `--dry-run` to print planned apt or download actions without creating the
version directory:

```bash
tt-env install --dry-run 2024.1
```

## Rollback behavior

Installs are staged in `${TT_HOME}/versions/.<release>.partial` and moved into
place only after all steps succeed. If apt, download, or sha256 verification
fails, `tt-env` removes the partial directory and leaves no broken version
directory. During `--force`, the previous installed version is kept until the
new install has completed successfully.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `sudo is required to install <manager> packages` | Install or enable `sudo`, or use a manifest with `USE_SYSTEM_PACKAGES="false"` and component download URLs. Applies to apt and dnf system package paths. |
| `add-apt-repository is required to add repositories` | Install `software-properties-common`. |
| `dnf config-manager is required to add repositories` | Install `dnf-plugins-core` before using a dnf manifest with repositories. |
| `curl is required to download release artifacts` | Install `curl` before using the fallback path. |
| `sha256 mismatch` | Check the stack manifest `sha256` values and artifact URLs; the partial install is rolled back. |
| `Version directory exists but is not marked installed` | Inspect the directory and rerun with `--force` if it is safe to recreate. |
