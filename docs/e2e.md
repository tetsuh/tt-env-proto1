# Ubuntu end-to-end verification

This checklist verifies proto1 on a real supported Ubuntu host. It covers
`install`, `use`, `status`, `update`, and `update --self`.

Hosted CI covers shellcheck and Bats only. Record the command transcript, host
notes, and any deviations in the pull request that depends on this manual run.

Supported Ubuntu releases for proto1:

| Release | Manifest | Hosted CI | Manual E2E |
| --- | --- | --- | --- |
| Ubuntu 22.04 | `ubuntu-22.04.env` | Yes | Required for hardware/system changes affecting 22.04 |
| Ubuntu 24.04 | `ubuntu-24.04.env` | Yes | Required for hardware/system changes affecting 24.04 |

Unofficial compatibility targets:

| Release | Manifest | Hosted CI | Manual E2E |
| --- | --- | --- | --- |
| Linux Mint 22.1 | `linuxmint-22.1.env` | Parser and Bats coverage only | Required before relying on KMD or hardware/system behavior |

Fedora-family manifests are currently test fixtures only. They exercise the dnf
adapter in automated tests, but Fedora is not a supported manual E2E target
until real Fedora hardware/system validation is completed.

## 1. Host prerequisites

Use an Ubuntu 22.04, Ubuntu 24.04, or Linux Mint 22.1 machine with Secure Boot disabled.

```bash
cat /etc/os-release | grep -E '^(ID|VERSION_ID)='
mokutil --sb-state
command -v bash curl gpg sudo apt-get add-apt-repository lspci >/dev/null
```

Expected output:

```text
ID=<ubuntu or linuxmint>
VERSION_ID="<22.04, 24.04, or 22.1>"
SecureBoot disabled
```

If the companion manifest repository is private, authenticate before running
`tt-env update`:

```bash
export GITHUB_TOKEN="<token with repo read access>"
# or:
gh auth status
```

## 2. Bootstrap tt-env

From a clean clone:

```bash
git clone https://github.com/tetsuh/tt-env-proto1.git
cd tt-env-proto1
bash install.sh
export PATH="${HOME}/.tt-env/shims:${HOME}/.tt-env/bin:${PATH}"
tt-env --version
```

Expected output:

```text
0.2.0
```

Proto1-managed GPG signatures are temporarily suspended. Do not expect
`${HOME}/.tt-env/keys` to contain a trusted proto1 signing key on a fresh
install.

## 3. Refresh manifests

```bash
tt-env update
```

Expected output:

```text
[INFO] Updated manifests from tetsuh/tt-env-manifests-proto1@main.
```

Confirm local manifest cache files exist:

```bash
os_version="$(. /etc/os-release && printf '%s' "${VERSION_ID}")"
test -f "${HOME}/.tt-env/releases/2026.05.16.json"
test -f "${HOME}/.tt-env/manifests/ubuntu-${os_version}.env"
test -f "${HOME}/.tt-env/manifests/last_update"
```

## 4. Install a stack release

```bash
tt-env install 2026.05.16
```

The repository Ubuntu and Linux Mint manifests configure the official signed
Tenstorrent apt repository at `https://ppa.tenstorrent.com/ubuntu/`. Expected
output includes adding the repository, updating package metadata, and installing
the resolved packages:

```text
[INFO] Adding apt repository: https://ppa.tenstorrent.com/ubuntu/
[INFO] Updating apt package metadata.
[INFO] Installing apt packages: cmake ninja-build zlib1g-dev tenstorrent-dkms
[INFO] Installed release 2026.05.16 at /home/<user>/.tt-env/versions/2026.05.16.
```

If the host codename is not one of the currently published Tenstorrent apt
pockets (`jammy` or `noble`), `tt-env` fails before writing an apt source entry.
If a validation run instead provides a stack manifest with component download
URLs and sha256 metadata and disables system packages, expected output includes
artifact downloads and final install success:

```text
[INFO] Downloading <component> from <url>
[INFO] Installed release 2026.05.16 at /home/<user>/.tt-env/versions/2026.05.16.
```

Verify the install marker:

```bash
test -f "${HOME}/.tt-env/versions/2026.05.16/.tt-env-installed"
```

## 5. Activate the release

```bash
tt-env use 2026.05.16
readlink "${HOME}/.tt-env/current"
```

Expected output:

```text
[INFO] Using release 2026.05.16 at /home/<user>/.tt-env/versions/2026.05.16.
/home/<user>/.tt-env/versions/2026.05.16
```

If the release contains `tt-smi`, verify shim dispatch:

```bash
command -v tt-smi
tt-smi --version
```

Expected `command -v` output:

```text
/home/<user>/.tt-env/shims/tt-smi
```

If `tt-smi --version` fails on a host without Tenstorrent hardware or runtime
support, record stderr and continue. On a hardware-equipped verification host,
treat the failure as a blocker.

## 6. Inspect status

```bash
tt-env status
```

Expected output shape:

```text
Status
Tenstorrent hardware: <n> device(s)
Active release: 2026.05.16
KMD module version: <version or (not loaded)>
Manifest freshness: <freshness>
```

On Tenstorrent hardware, device lines should also be printed below the summary.
On hosts without hardware, `Tenstorrent hardware: 0 device(s)` is acceptable for
proto1 command verification.

## 7. Verify self-update no-op and replacement paths

First verify the normal no-op path when local and remote `VERSION` match:

```bash
tt-env update --self
```

Expected output when the remote version equals the local version:

```text
[INFO] tt-env is already up to date (0.2.0).
```

For a replacement-path smoke test, use an isolated copy as the self-update target
so the repository checkout is not mutated:

```bash
tmp_dir="$(mktemp -d)"
cp bin/tt-env "${tmp_dir}/tt-env"
chmod +x "${tmp_dir}/tt-env"
before_hash="$(sha256sum "${tmp_dir}/tt-env" | awk '{print $1}')"

TT_SELF_UPDATE_TARGET_FILE="${tmp_dir}/tt-env" \
TT_SELF_UPDATE_LOCAL_VERSION_FILE=VERSION \
tt-env update --self

after_hash="$(sha256sum "${tmp_dir}/tt-env" | awk '{print $1}')"
printf 'before=%s\nafter=%s\n' "$before_hash" "$after_hash"
rm -rf "$tmp_dir"
```

If a newer `bin/tt-env` exists at the configured remote ref, expected output
includes:

```text
[INFO] Self-update available: 0.2.0 -> <remote-version>.
[INFO] Updated tt-env to <remote-version>.
```

If no newer binary exists, the no-op output is acceptable.

## 8. Final evidence to capture

Attach these to the PR manual verification log:

1. Host OS and Secure Boot output.
2. `tt-env --version`.
3. Note that proto1-managed GPG signing is suspended.
4. `tt-env update` result.
5. `tt-env install 2026.05.16` result.
6. `tt-env use 2026.05.16` and `readlink ~/.tt-env/current`.
7. `tt-env status` output.
8. `tt-env update --self` output.
