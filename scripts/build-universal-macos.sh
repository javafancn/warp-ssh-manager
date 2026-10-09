#!/usr/bin/env bash
# Candidate, ad-hoc signed Universal 2 .app; does not replace notarized distribution.
set -euo pipefail
[[ "$(uname -s)" == Darwin ]] || { echo 'Build on macOS.' >&2; exit 1; }
command -v cargo >/dev/null && command -v lipo >/dev/null && command -v rustup >/dev/null \
  || { echo 'Cargo, rustup and Xcode CLI tools required.' >&2; exit 1; }
cd "$(dirname "$0")/.."
export MACOSX_DEPLOYMENT_TARGET=12.0
rustup target add aarch64-apple-darwin x86_64-apple-darwin
cargo build -p wsm-desktop --features tray --release --target aarch64-apple-darwin
cargo build -p wsm-desktop --features tray --release --target x86_64-apple-darwin
app_dir='target/universal/Warp SSH Manager.app'
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
lipo -create \
  target/aarch64-apple-darwin/release/warp-ssh-manager \
  target/x86_64-apple-darwin/release/warp-ssh-manager \
  -output "$app_dir/Contents/MacOS/warp-ssh-manager"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleExecutable</key><string>warp-ssh-manager</string>
<key>CFBundleIdentifier</key><string>dev.warpsshmanager.app</string>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>CFBundleName</key><string>Warp SSH Manager</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3</string>
<key>CFBundleVersion</key><string>3</string>
<key>LSMinimumSystemVersion</key><string>12.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
plutil -lint "$app_dir/Contents/Info.plist"
# Ad-hoc local signature: external distribution needs a real Developer ID and notarization.
codesign --force --sign - --timestamp=none "$app_dir"
bash scripts/verify-macos-binary.sh "$app_dir" --universal
printf '\nCandidate local app: %s\nNo Developer ID signing / notarization performed.\n' "$app_dir"
