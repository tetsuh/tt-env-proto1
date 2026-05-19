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
    TT_STACK_SYSTEM_PACKAGES[kmd]="2.8.0"
    TT_STACK_SYSTEM_PACKAGES[smi]="5.0.1"
    TT_STACK_SYSTEM_PACKAGES[flash]="3.6.5"
    TT_STACK_SYSTEM_PACKAGES[topology]="1.2.19"
    TT_STACK_SYSTEM_PACKAGES[burnin]="0.4.0"
    package_manager_install_system_packages dnf 1
  ' bash "$PACKAGE_MANAGER_SH" "$FEDORA_MANIFEST"

  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] Would run dnf makecache."* ]]
  [[ "$output" == *"[dry-run] Would install dnf packages: cmake ninja-build zlib-devel tenstorrent-dkms-2.8.0 tt-smi-5.0.1 tt-flash-3.6.5 tt-topology-1.2.19 tt-burnin-0.4.0"* ]]
}
