#!/usr/bin/env bash
set -euo pipefail
if [[ "$(uname -s)" != 'Darwin' ]]; then echo 'Build macOS .app on a Mac.' >&2; exit 1; fi
command -v cargo >/dev/null || { echo 'Rust/Cargo missing.' >&2; exit 1; }
# Deployment target is a build intent; actual Monterey runtime compatibility must be tested.
export MACOSX_DEPLOYMENT_TARGET=12.0
cargo fmt --all -- --check
cargo test -p wsm-core
cargo check -p wsm-cli
cargo check -p wsm-desktop --features tray
cargo install cargo-bundle --locked
cargo bundle -p wsm-desktop --release --features tray
printf '\nBundle generated under target/release/bundle/osx/ (exact path depends on cargo-bundle).\n'
printf 'Sign and notarize before external distribution. This script does not claim to do so.\n'
