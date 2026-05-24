#!/usr/bin/env bats

setup() {
  TT_ENV="${BATS_TEST_DIRNAME}/../../bin/tt-env"
  MANIFEST_PARSER="${BATS_TEST_DIRNAME}/../../lib/manifest_parser.sh"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export TT_HOME="${BATS_TEST_TMPDIR}/tt-home"
  export TT_OVERRIDE_OS_ID="ubuntu"
  export TT_OVERRIDE_OS_VERSION="24.04"
  mkdir -p "${TT_HOME}/releases" "${TT_HOME}/manifests"
  write_os_manifest
  write_base_manifest
}

write_os_manifest() {
  cat >"${TT_HOME}/manifests/ubuntu-24.04.env" <<'EOF'
PKG_MANAGER="apt"
USE_SYSTEM_PACKAGES="true"
REQUIRED_REPOS=(
  "https://ppa.tenstorrent.com/ubuntu/"
)
VIRT_PKG_CMAKE="cmake"
VIRT_PKG_NINJA="ninja-build"
VIRT_PKG_ZLIB="zlib1g-dev"
VIRT_PKG_KMD="tenstorrent-dkms"
VIRT_PKG_SMI="tt-smi"
VIRT_PKG_FLASH="tt-flash"
VIRT_PKG_TOPOLOGY="tt-topology"
VIRT_PKG_METALIUM="tt-metalium"
WORKAROUNDS=()
EOF
}

write_base_manifest() {
  cat >"${TT_HOME}/releases/2026.05.16.json" <<'EOF'
{
  "release": "2026.05.16",
  "description": "Base stack",
  "components": {
    "tt-kmd": "ttkmd-2.7.0",
    "tt-smi": "v5.1.0",
    "firmware": "v19.6.0",
    "tt-metal": "v0.70.1"
  },
  "system_packages": {
    "kmd": "2.7.0",
    "smi": "5.0.0",
    "flash": "3.6.4",
    "topology": "1.2.18",
    "metalium": "0.68.0~ubuntu24.04"
  },
  "python_packages": {
    "tt-smi": "5.1.0",
    "tt-umd": "0.9.4",
    "textual": "0.59.0",
    "elasticsearch": "8.11.0",
    "tt-burnin": "0.3.0"
  },
  "git_components": {
    "tt-studio": {
      "url": "https://github.com/tenstorrent/tt-studio.git",
      "version": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    },
    "tt-inference-server": {
      "url": "https://github.com/tenstorrent/tt-inference-server.git",
      "version": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    }
  },
  "container_components": {
    "tt-metalium": {
      "ref": "tt-metalium-ubuntu24"
    },
    "tt-metalium-ubuntu24": {
      "image_url": "ghcr.io/tenstorrent/tt-metal/tt-metalium-ubuntu-24.04-release-amd64",
      "image_tag": "sha256:1111111111111111111111111111111111111111111111111111111111111111"
    }
  }
}
EOF
}

make_capture_fake_bin() {
  local fake_bin="${BATS_TEST_TMPDIR}/fake-bin"

  mkdir -p "$fake_bin"
  cat >"${fake_bin}/apt-cache" <<'EOF'
#!/usr/bin/env bash
case "${2:-}" in
  tenstorrent-dkms) printf 'tenstorrent-dkms | 2.8.0 | repo\n' ;;
  tt-smi) printf 'tt-smi | 5.0.1 | repo\n' ;;
  tt-flash) printf 'tt-flash | 3.6.5 | repo\n' ;;
  tt-topology) printf 'tt-topology | 1.2.19 | repo\n' ;;
  tt-metalium) printf 'tt-metalium | 0.69.0~ubuntu24.04 | repo\n' ;;
  *) exit 1 ;;
esac
EOF
  cat >"${fake_bin}/curl" <<'EOF'
#!/usr/bin/env bash
headers_file=""
url=""
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --dump-header)
      shift
      headers_file="$1"
      ;;
    https://*)
      url="$1"
      ;;
  esac
  shift
done
case "$url" in
  https://pypi.org/pypi/tt-smi/json) printf '{"info":{"version":"5.2.0"}}\n' ;;
  https://pypi.org/pypi/tt-umd/json) printf '{"info":{"version":"0.9.5"}}\n' ;;
  https://pypi.org/pypi/textual/json) printf '{"info":{"version":"8.2.7"}}\n' ;;
  https://pypi.org/pypi/elasticsearch/json) printf '{"info":{"version":"9.4.0"}}\n' ;;
  https://pypi.org/pypi/tt-burnin/json) printf '{"info":{"version":"0.4.0"}}\n' ;;
  https://ghcr.io/token*) printf '{"token":"test-token"}\n' ;;
  https://ghcr.io/v2/*/manifests/latest)
    printf 'Docker-Content-Digest: sha256:2222222222222222222222222222222222222222222222222222222222222222\r\n' >"$headers_file"
    ;;
  *) exit 1 ;;
esac
EOF
  cat >"${fake_bin}/git" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"--tags --refs"* ]]; then
  printf 'cccccccccccccccccccccccccccccccccccccccc\trefs/tags/v0.72.0-dev20260524\n'
  printf 'dddddddddddddddddddddddddddddddddddddddd\trefs/tags/not-a-release\n'
  exit 0
fi
case "$*" in
  *tt-studio.git*)
    printf 'ref: refs/heads/main\tHEAD\n'
    printf 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\tHEAD\n'
    ;;
  *tt-inference-server.git*)
    printf 'ref: refs/heads/main\tHEAD\n'
    printf 'ffffffffffffffffffffffffffffffffffffffff\tHEAD\n'
    ;;
  *)
    exit 1
    ;;
esac
EOF
  chmod +x "${fake_bin}/apt-cache" "${fake_bin}/curl" "${fake_bin}/git"
  printf '%s\n' "$fake_bin"
}

@test "tt-env capture creates a local-only manifest from latest metadata" {
  fake_bin="$(make_capture_fake_bin)"

  run env PATH="${fake_bin}:${PATH}" "$TT_ENV" capture 2026.05.24

  [ "$status" -eq 0 ]
  [[ "$output" == *"Captured local release manifest: ${TT_HOME}/releases/2026.05.24.json"* ]]
  [ -f "${TT_HOME}/releases/2026.05.24.json" ]

  run bash -c '
    source "$1"
    parse_stack_manifest "$2"
    printf "%s\n" "$TT_STACK_RELEASE"
    printf "%s\n" "${TT_STACK_COMPONENTS[tt-kmd]}"
    printf "%s\n" "${TT_STACK_COMPONENTS[tt-metal]}"
    printf "%s\n" "${TT_STACK_SYSTEM_PACKAGES[metalium]}"
    printf "%s\n" "${TT_STACK_PYTHON_PACKAGES[textual]}"
    printf "%s\n" "${TT_STACK_GIT_COMPONENTS_VERSION[tt-studio]}"
    printf "%s\n" "${TT_STACK_CONTAINER_COMPONENTS_IMAGE_TAG[tt-metalium]}"
  ' bash "$MANIFEST_PARSER" "${TT_HOME}/releases/2026.05.24.json"

  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "2026.05.24" ]
  [ "${lines[1]}" = "ttkmd-2.8.0" ]
  [ "${lines[2]}" = "v0.72.0-dev20260524" ]
  [ "${lines[3]}" = "0.69.0~ubuntu24.04" ]
  [ "${lines[4]}" = "8.2.7" ]
  [ "${lines[5]}" = "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee" ]
  [ "${lines[6]}" = "sha256:2222222222222222222222222222222222222222222222222222222222222222" ]
}

@test "tt-env capture dry-run prints manifest without writing it" {
  fake_bin="$(make_capture_fake_bin)"

  run env PATH="${fake_bin}:${PATH}" "$TT_ENV" capture --dry-run 2026.05.24

  [ "$status" -eq 0 ]
  [[ "$output" == *'"release": "2026.05.24"'* ]]
  [ ! -e "${TT_HOME}/releases/2026.05.24.json" ]
}

@test "tt-env capture refuses to overwrite unless forced" {
  fake_bin="$(make_capture_fake_bin)"
  cp "${TT_HOME}/releases/2026.05.16.json" "${TT_HOME}/releases/2026.05.24.json"

  run env PATH="${fake_bin}:${PATH}" "$TT_ENV" capture 2026.05.24

  [ "$status" -eq 1 ]
  [[ "$output" == *"Release manifest already exists:"* ]]
  [[ "$output" == *"Use --force to overwrite"* ]]
}

@test "tt-env capture help documents local snapshot options" {
  run "$TT_ENV" help capture

  [ "$status" -eq 0 ]
  [[ "$output" == *"tt-env capture - capture a local-only stack release manifest"* ]]
  [[ "$output" == *"--dry-run"* ]]
  [[ "$output" == *"--force"* ]]
  [[ "$output" == *"--base"* ]]
}
