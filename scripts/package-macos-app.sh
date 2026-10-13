#!/usr/bin/env bash
# Assemble a macOS application bundle from previously compiled native Mach-O executable(s).
# The output is ad-hoc signed for local testing, NOT notarized for general distribution.
set -euo pipefail
[[ "$(uname -s)" == 'Darwin' ]] || { echo 'Requires macOS and Apple developer tools.' >&2; exit 1; }
[[ $# == 3 ]] || { echo 'Usage: bash scripts/package-macos-app.sh --single <binary> <apple-silicon|intel>' >&2; exit 2; }
mode="$1"
case "$mode" in
  --single) ;;
  *) echo 'Only separate architecture installers are supported.' >&2; exit 2 ;;
esac
arch="$3"
case "$arch" in
  apple-silicon) expected_arch=arm64 ;;
  intel) expected_arch=x86_64 ;;
  *) echo "Unknown architecture: $arch" >&2; exit 2 ;;
esac
for tool in lipo codesign ditto hdiutil sips iconutil plutil; do
  command -v "$tool" >/dev/null || { echo "Missing $tool (install Xcode Command Line Tools)" >&2; exit 1; }
done
project="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project"
mkdir -p dist
app='dist/Warp SSH Manager.app'
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
exe="$app/Contents/MacOS/warp-ssh-manager"
[[ -s "$2" ]] || { echo "Executable not found: $2" >&2; exit 1; }
cp "$2" "$exe"
# SwiftUI is the executable; the original Rust core remains the only SSH/DB writer.
case "$arch" in
  apple-silicon) rust_target=aarch64-apple-darwin ;;
  intel) rust_target=x86_64-apple-darwin ;;
esac
rust_cli="target/${rust_target}/release/wsm"
[[ -s "$rust_cli" ]] || { echo "Missing Rust core CLI: $rust_cli" >&2; exit 1; }
cp "$rust_cli" "$app/Contents/MacOS/wsm"
chmod 755 "$app/Contents/MacOS/wsm"
[[ "$(lipo -archs "$app/Contents/MacOS/wsm")" == "$expected_arch" ]] || {
    echo 'Rust core architecture mismatch.' >&2; exit 1;
}
found_archs="$(lipo -archs "$exe")"
[[ "$found_archs" == "$expected_arch" ]] || { echo "Architecture mismatch: wanted $expected_arch, got $found_archs" >&2; exit 1; }
chmod 755 "$exe"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
<key>CFBundleExecutable</key><string>warp-ssh-manager</string>
<key>CFBundleIdentifier</key><string>dev.warpsshmanager.app</string>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>CFBundleName</key><string>Warp SSH 管理器</string>
<key>CFBundleDisplayName</key><string>Warp SSH 管理器</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.4.25</string>
<key>CFBundleVersion</key><string>36</string>
<key>CFBundleIconFile</key><string>WarpSSHManager</string>
<key>LSMinimumSystemVersion</key><string>12.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
plutil -lint "$app/Contents/Info.plist"
# Use the exact user-approved images extracted from the supplied brand board:
# dark rounded-square icon for Finder/Dock/Launchpad, transparent chevron in the UI.
# The checked-in PNGs are compressed masters; sips creates every macOS iconset size.
[[ -s assets/brand-app-icon.png && -s assets/brand-mark.png ]] || { echo 'Approved PNG assets are missing.' >&2; exit 1; }
sips -s format png -z 1024 1024 assets/brand-app-icon.png --out dist/brand-app-icon-1024.png >/dev/null
cp assets/brand-mark.png "$app/Contents/Resources/brand-mark.png"
cp assets/brand-app-icon.png "$app/Contents/Resources/brand-app-icon.png"
[[ -s dist/brand-app-icon-1024.png && -s "$app/Contents/Resources/brand-mark.png" ]] || { echo 'Brand resources failed validation.' >&2; exit 1; }
# Convert the generated artwork into an Apple .icns using macOS tools.
iconset='dist/WarpSSHManager.iconset'
rm -rf "$iconset"
mkdir -p "$iconset"
for n in 16 32 128 256 512; do
  sips -s format png -z "$n" "$n" dist/brand-app-icon-1024.png --out "$iconset/icon_${n}x${n}.png" >/dev/null
  size=$((n*2))
  sips -s format png -z "$size" "$size" dist/brand-app-icon-1024.png --out "$iconset/icon_${n}x${n}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/WarpSSHManager.icns"
rm -rf "$iconset"
[[ -s "$app/Contents/Resources/WarpSSHManager.icns" ]] || { echo 'Brand .icns generation failed.' >&2; exit 1; }
# Fail CI before distributing an app whose Dock or internal logo failed to bundle.
[[ -s "$app/Contents/Resources/brand-mark.png" ]] || { echo 'Internal brand PNG not bundled.' >&2; exit 1; }
[[ -s "$app/Contents/Resources/brand-app-icon.png" ]] || { echo 'Internal app icon PNG not bundled.' >&2; exit 1; }
sips -g pixelWidth -g pixelHeight "$app/Contents/Resources/brand-mark.png" >/dev/null
sips -g pixelWidth -g pixelHeight "$app/Contents/Resources/WarpSSHManager.icns" >/dev/null
# Ad-hoc signing is appropriate for local test builds; it is not Developer ID notarization.
codesign --force --sign - --timestamp=none "$app/Contents/MacOS/wsm"
codesign --force --sign - --timestamp=none "$app"
codesign --verify --verbose=2 "$app"
"$app/Contents/MacOS/wsm" --version
bash scripts/verify-macos-binary.sh "$app"
zip_path="dist/WarpSSHManager-0.4.25-${arch}.app.zip"
dmg_path="dist/WarpSSHManager-0.4.25-${arch}.dmg"
rm -f "$zip_path" "$dmg_path"
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip_path"
# Finder-style drag-to-Applications installer instead of a raw .app disk image.
staging="dist/dmg-${arch}"
rm -rf "$staging"
mkdir -p "$staging"
ditto "$app" "$staging/Warp SSH Manager.app"
ln -s /Applications "$staging/Applications"
# macOS runners occasionally return EBUSY while Spotlight or disk image services
# briefly access the staging directory. Retry safely before failing the build.
created=0
for attempt in 1 2 3 4; do
  rm -f "$dmg_path"
  if hdiutil create -volname "Warp SSH Manager (${arch})" \
      -srcfolder "$staging" -ov -format UDZO "$dmg_path" >/dev/null; then
    created=1
    break
  fi
  echo "DMG creation attempt ${attempt}/4 failed; retrying..." >&2
  sleep $((attempt * 3))
done
[[ "$created" == 1 && -s "$dmg_path" ]] || { echo "DMG creation failed after 4 attempts" >&2; exit 1; }
hdiutil imageinfo "$dmg_path" >/dev/null || { echo "DMG validation failed" >&2; exit 1; }
rm -rf "$staging"
printf '\nBuild artifacts:\n  %s\n  %s\n\n' "$zip_path" "$dmg_path"
printf 'This build is AD-HOC signed, NOT APPLE NOTARIZED. Run macOS 12 and SSH integration smoke tests before general use.\n'
