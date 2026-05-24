# Capturing dated release manifests

Create dated release manifests regularly so `tt-env` can compare and switch
between Tenstorrent stack snapshots such as `2026.05.16` and `2026.08.16`.

This workflow is best-effort. It records version pins that upstream package
repositories can currently resolve; `tt-env` does not mirror apt/dnf packages,
PyPI wheels, firmware bundles, or container images.

## Local-only capture command

Use `tt-env capture` to create a personal snapshot manifest without publishing it
to the manifests repository:

```sh
tt-env capture 2026.05.24
tt-env diff 2026.05.16 2026.05.24
tt-env install --dry-run 2026.05.24
```

The command writes only to `~/.tt-env/releases/<release>.json`. It uses the
newest existing dated manifest as a template unless `--base <release>` is
provided, refuses to overwrite an existing local manifest unless `--force` is
provided, and supports `--dry-run` to print the generated JSON.

`tt-env capture` queries the currently configured apt metadata, PyPI, git
remotes, and GHCR image metadata. It is intended for local experimentation; do
not rely on KMD, system package, or hardware behavior without real hardware
validation.

## Manual capture workflow

Use this workflow when you want to curate or publish a manifest rather than
creating a local-only snapshot.

## 1. Choose the release name

Use the date that represents the stack snapshot:

```sh
release=2026.08.16
cp releases/2026.05.16.json "releases/${release}.json"
```

Edit the copied manifest's `release` and `description` fields.

## 2. Capture system package versions

Query the package manager for available Tenstorrent package versions and choose
the versions that define the release:

```sh
apt-cache madison tenstorrent-dkms tt-smi tt-flash tt-topology
# Fedora-family fixtures or future Fedora support:
dnf --showduplicates list tenstorrent-dkms tt-smi tt-flash tt-topology
```

Record the selected versions under `system_packages` using virtual package
keys:

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

Use exact package-manager versions. If a selected version later disappears from
the upstream repository, installing that dated release should fail clearly.

## 3. Capture Python package versions

Record release-local Python dependencies under `python_packages`. Use pinned
versions only:

```sh
python3 -m pip index versions tt-umd
python3 -m pip index versions textual
python3 -m pip index versions elasticsearch
python3 -m pip index versions tt-burnin
```

```json
{
  "python_packages": {
    "tt-umd": "0.9.5",
    "textual": "0.59.0",
    "elasticsearch": "8.11.0",
    "tt-burnin": "0.4.0"
  }
}
```

## 4. Capture manually tracked components

Update `components` for versions that are not fully represented by package
manager pins, such as firmware, tt-metal, or container/image tags:

```json
{
  "components": {
    "tt-kmd": "ttkmd-2.8.0",
    "tt-smi": "v5.2.0",
    "firmware": "v19.6.0",
    "tt-metal": "v0.70.1"
  }
}
```

The `components` values are comparison metadata unless a component entry uses
the downloadable object form with `download_url` and `sha256`.

## 5. Validate the new manifest

Run the parser tests and compare the new release against the previous one.
Use `tt-env diff` when that command is available; otherwise compare the JSON
manifests directly:

```sh
bash scripts/test.sh
tt-env diff 2026.05.16 "${release}"
# Fallback before tt-env diff is available:
diff releases/2026.05.16.json "releases/${release}.json"
```

Then install and switch releases on real hardware if the package pins are
intended to be operational:

```sh
tt-env install "${release}"
tt-env use "${release}"
tt-smi
```

Remember that KMD is system-global. `tt-env use` can switch release-local
wrappers and shims, but it cannot switch an already-loaded kernel module by
symlink alone.
