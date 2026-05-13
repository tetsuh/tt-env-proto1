# Ubuntu 22.04 end-to-end verification

This checklist verifies proto1 on a real Ubuntu 22.04 host. It covers
`install`, `use`, `status`, `update`, and `update --self`.

Proto1 has no hosted CI. Record the command transcript, host notes, and any
deviations in the pull request that depends on this manual run.

## 1. Host prerequisites

Use an Ubuntu 22.04 machine with Secure Boot disabled.

```bash
cat /etc/os-release | grep -E '^(ID|VERSION_ID)='
mokutil --sb-state
command -v bash curl gpg sudo apt-get add-apt-repository lspci >/dev/null
```

Expected output:

```text
ID=ubuntu
VERSION_ID="22.04"
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
0.1.0
```

Verify the trusted proto1 signing key was bootstrapped:

```bash
gpg --homedir "${HOME}/.tt-env/keys" --with-colons --fingerprint |
  awk -F: '$1 == "fpr" { print $10 }'
```

Expected fingerprint:

```text
C55FEB196FB67D83F63FE18CBEF418235C011DF8
```

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
test -f "${HOME}/.tt-env/releases/2024.1.json"
test -f "${HOME}/.tt-env/manifests/ubuntu-22.04.env"
test -f "${HOME}/.tt-env/manifests/last_update"
```

## 4. Install a stack release

```bash
tt-env install 2024.1
```

Expected PPA-path output includes:

```text
[INFO] Adding apt repository: ppa:tenstorrent/ppa
[INFO] Updating apt package metadata.
[INFO] Installing apt packages: cmake ninja-build zlib1g-dev tt-kmd-dkms
[INFO] Installed release 2024.1 at /home/<user>/.tt-env/versions/2024.1.
```

If the manifest uses the fallback download path instead of PPA, expected output
includes signed artifact downloads and final install success:

```text
[INFO] Downloading <component> from <url>
[INFO] Installed release 2024.1 at /home/<user>/.tt-env/versions/2024.1.
```

Verify the install marker:

```bash
test -f "${HOME}/.tt-env/versions/2024.1/.tt-env-installed"
```

## 5. Activate the release

```bash
tt-env use 2024.1
readlink "${HOME}/.tt-env/current"
```

Expected output:

```text
[INFO] Using release 2024.1 at /home/<user>/.tt-env/versions/2024.1.
/home/<user>/.tt-env/versions/2024.1
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
Active release: 2024.1
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
[INFO] tt-env is already up to date (0.1.0).
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

If a newer signed `bin/tt-env` exists at the configured remote ref, expected
output includes:

```text
[INFO] Self-update available: 0.1.0 -> <remote-version>.
[INFO] Updated tt-env to <remote-version>.
```

If no newer signed binary exists, the no-op output is acceptable.

## 8. Final evidence to capture

Attach these to the PR manual verification log:

1. Host OS and Secure Boot output.
2. `tt-env --version`.
3. Trusted key fingerprint.
4. `tt-env update` result.
5. `tt-env install 2024.1` result.
6. `tt-env use 2024.1` and `readlink ~/.tt-env/current`.
7. `tt-env status` output.
8. `tt-env update --self` output.
