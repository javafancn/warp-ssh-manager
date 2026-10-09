#!/bin/bash
# Finder-launchable local build helper. Requires Xcode CLI tools, Rust/Cargo and internet for first dependency fetch.
set -euo pipefail
cd "$(dirname "$0")"
if [[ "$(uname -s)" != 'Darwin' ]]; then
  echo 'This builder must run on a Mac.'
  exit 1
fi
printf 'Warp SSH Manager / macOS local application builder\n\n'
if ! xcode-select -p >/dev/null 2>&1 || ! xcrun --find clang >/dev/null 2>&1; then
  echo 'Xcode Command Line Tools are required. Run: xcode-select --install'
  exit 1
fi
if ! command -v cargo >/dev/null 2>&1; then
  [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
fi
if ! command -v cargo >/dev/null 2>&1; then
  echo 'Rust/Cargo is missing. Install Rust from https://rustup.rs and start this builder again.'
  exit 1
fi
export MACOSX_DEPLOYMENT_TARGET=12.0
cargo build -p wsm-desktop --release --features tray
bash scripts/package-macos-app.sh --single "$(pwd)/target/release/warp-ssh-manager"
printf '\nYour app is under: %s/dist/Warp SSH Manager.app\n' "$(pwd)"
open dist
