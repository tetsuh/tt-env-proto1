#!/usr/bin/env bats

setup() {
  REPO_DIR="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  PACKAGE_MANAGER_SH="${REPO_DIR}/lib/package_manager.sh"
  FEDORA_MANIFEST="${REPO_DIR}/tests/fixtures/manifests/fedora-40.env"
}

@test "Fedora fixture resolves dnf package mappings" {
  run bash -c '
    source "$1"
    parse_env_manifest "$2"
    package_manager_install_system_packages dnf 1
  ' bash "$PACKAGE_MANAGER_SH" "$FEDORA_MANIFEST"

  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] Would run dnf makecache."* ]]
  [[ "$output" == *"[dry-run] Would install dnf packages: cmake ninja-build zlib-devel tt-kmd-dkms"* ]]
}
