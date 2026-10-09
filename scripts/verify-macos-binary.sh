#!/usr/bin/env bash
# Verify architecture slices and deployment versions in Mach-O; runtime verification remains separate.
set -euo pipefail
[[ "$(uname -s)" == Darwin ]] || { echo 'Verification must run on a Mac.' >&2; exit 1; }
[[ $# -ge 1 ]] || { echo "Usage: $0 /path/to/binary-or-app [--universal]" >&2; exit 2; }
input="$1"
if [[ -d "$input" ]]; then
  binary="$input/Contents/MacOS/warp-ssh-manager"
  plist="$input/Contents/Info.plist"
  if [[ -f "$plist" ]]; then
    minimum="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$plist")"
    echo "App Info.plist minimum: $minimum"
    [[ "$minimum" == '12.0' ]] || { echo 'App minimum system version is not 12.0' >&2; exit 1; }
  fi
else
  binary="$input"
fi
[[ -f "$binary" ]] || { echo "Executable not found: $binary" >&2; exit 1; }
archs="$(lipo -archs "$binary")"
echo "Architectures: $archs"
if [[ "${2:-}" == '--universal' ]]; then
  [[ " $archs " == *" x86_64 "* && " $archs " == *" arm64 "* ]] \
    || { echo 'Missing Intel or Apple Silicon slice.' >&2; exit 1; }
fi
for arch in $archs; do
  echo "Mach-O deployment info ($arch):"
  otool -l -arch "$arch" "$binary" | awk '
    $1 == "cmd" && ($2 == "LC_BUILD_VERSION" || $2 == "LC_VERSION_MIN_MACOSX") { enabled=1; next }
    enabled && $1 == "minos" { print "  minos " $2; if ($2+0 > 12.0) bad=1; enabled=0; found=1 }
    enabled && $1 == "version" { print "  version " $2; if ($2+0 > 12.0) bad=1; enabled=0; found=1 }
    END { if (!found) { print "  No deployment metadata found"; exit 2 } if (bad) exit 1 }
  ' || { echo "Minimum OS exceeds 12.0 or could not be parsed for $arch" >&2; exit 1; }
done
printf 'PASS: architecture / deployment metadata only; macOS 12 runtime and UI must still be tested.\n'
