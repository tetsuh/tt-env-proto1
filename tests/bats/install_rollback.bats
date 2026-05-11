#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/test_helpers.bash"
  install_test_setup_common
}

make_failing_sudo() {
  local fake_bin="${BATS_TEST_TMPDIR}/failing-apt-bin"

  mkdir -p "$fake_bin"
  cat >"${fake_bin}/sudo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TT_APT_LOG"
if [[ "$1" == "apt-get" && "$2" == "install" ]]; then
  exit 42
fi
EOF
  chmod +x "${fake_bin}/sudo"
  touch "${fake_bin}/add-apt-repository" "${fake_bin}/apt-get"
  chmod +x "${fake_bin}/add-apt-repository" "${fake_bin}/apt-get"
  printf '%s\n' "$fake_bin"
}

make_failing_curl() {
  local fake_bin="${BATS_TEST_TMPDIR}/failing-curl-bin"

  mkdir -p "$fake_bin"
  cat >"${fake_bin}/curl" <<'EOF'
#!/usr/bin/env bash
output=""
url=""
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --output)
      output="$2"
      shift 2
      ;;
    file://*)
      url="$1"
      shift
      ;;
    *)
      shift
      ;;
  esac
done
printf '%s\n' "$url" >>"$TT_CURL_LOG"
if [[ "$url" == *"/firmware" ]]; then
  exit 55
fi
cp "${url#file://}" "$output"
EOF
  chmod +x "${fake_bin}/curl"
  printf '%s\n' "$fake_bin"
}

@test "forced apt failure removes the partial version directory" {
  fake_bin="$(make_failing_sudo)"
  write_install_os_manifest "true"

  run env PATH="${fake_bin}:${PATH}" "$TT_ENV" install 2024.1
  [ "$status" -eq 1 ]
  [[ "$output" == *"Failed to install apt packages"* ]]
  [ ! -e "${TT_HOME}/versions/2024.1" ]
  [ ! -e "${TT_HOME}/versions/.2024.1.partial" ]
}

@test "forced download failure removes the partial version directory" {
  fake_bin="$(make_failing_curl)"
  write_install_os_manifest "false"
  write_download_assets "rollback"
  write_download_release_manifest

  run env PATH="${fake_bin}:${PATH}" "$TT_ENV" install 2024.1
  [ "$status" -eq 1 ]
  [[ "$output" == *"Failed to download firmware"* ]]
  [ ! -e "${TT_HOME}/versions/2024.1" ]
  [ ! -e "${TT_HOME}/versions/.2024.1.partial" ]
}
