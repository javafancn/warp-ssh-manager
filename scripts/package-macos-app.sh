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
<key>CFBundleShortVersionString</key><string>0.3.2</string>
<key>CFBundleVersion</key><string>5</string>
<key>CFBundleIconFile</key><string>WarpSSHManager</string>
<key>LSMinimumSystemVersion</key><string>12.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
plutil -lint "$app/Contents/Info.plist"
# Convert the bundled PNG icon into an Apple .icns using macOS tools.
iconset='dist/WarpSSHManager.iconset'
rm -rf "$iconset"
mkdir -p "$iconset"
for n in 16 32 128 256 512; do
  sips -s format png -z "$n" "$n" assets/app-icon-1024.png --out "$iconset/icon_${n}x${n}.png" >/dev/null
  size=$((n*2))
  sips -s format png -z "$size" "$size" assets/app-icon-1024.png --out "$iconset/icon_${n}x${n}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/WarpSSHManager.icns"
rm -rf "$iconset"
# Ad-hoc signing is appropriate for local test builds; it is not Developer ID notarization.
codesign --force --sign - --timestamp=none "$app"
codesign --verify --verbose=2 "$app"
bash scripts/verify-macos-binary.sh "$app"
zip_path="dist/WarpSSHManager-0.3.2-${arch}.app.zip"
dmg_path="dist/WarpSSHManager-0.3.2-${arch}.dmg"
rm -f "$zip_path" "$dmg_path"
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip_path"
# Finder-style drag-to-Applications installer instead of a raw .app disk image.
staging="dist/dmg-${arch}"
rm -rf "$staging"
mkdir -p "$staging"
ditto "$app" "$staging/Warp SSH Manager.app"
ln -s /Applications "$staging/Applications"
hdiutil create -volname "Warp SSH Manager (${arch})" -srcfolder "$staging" -ov -format UDZO "$dmg_path" >/dev/null
rm -rf "$staging"
printf '\nBuild artifacts:\n  %s\n  %s\n\n' "$zip_path" "$dmg_path"
printf 'This build is AD-HOC signed, NOT APPLE NOTARIZED. Run macOS 12 and SSH integration smoke tests before general use.\n'
