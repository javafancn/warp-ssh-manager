#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo 'This smoke test is intended for macOS (isolated temp settings).' >&2
  exit 1
fi

base="$(mktemp -d)"
trap 'rm -rf "$base"' EXIT
export WSM_HOME="$base/app"
export WSM_SSH_CONFIG="$base/ssh/config"
export WSM_WARP_CONFIG_DIR="$base/warp/tab_configs"
mkdir -p "$base/ssh"
printf 'Host existing-test\n  HostName example.org\n  User alice\n' > "$WSM_SSH_CONFIG"

cargo run --quiet -p wsm-cli -- doctor
cargo run --quiet -p wsm-cli -- init
cargo run --quiet -p wsm-cli -- add --name 'Demo API' --alias demo-api --hostname example.com --user tester --favorite
cargo run --quiet -p wsm-cli -- sync

uuid="$(cargo run --quiet -p wsm-cli -- list | grep demo-api | awk '{print $1}')"
[[ -n "$uuid" ]]
# Capture the full CLI output before matching it. A `grep -q` pipeline closes
# stdout early, which can make Rust's println! panic with Broken pipe (os error 32)
# when `pipefail` is enabled.
dry_run_output="$(cargo run --quiet -p wsm-cli -- connect "$uuid" --dry-run)"
[[ "$dry_run_output" == *"ssh demo-api"* ]]
grep -q 'Host demo-api' "$base/ssh/config.d/warp-ssh-manager.conf"
[[ "$(grep -c '^Include ' "$WSM_SSH_CONFIG")" == 1 ]]
[[ -f "$base/warp/tab_configs/wsm_${uuid//-/}.toml" ]]

echo 'PASS: isolated init, add, list, sync, Warp TOML generation, dry-run.'
