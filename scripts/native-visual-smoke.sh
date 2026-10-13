#!/usr/bin/env bash
# Best-effort screenshot of the actual SwiftUI process on the macOS CI desktop.
# Fixtures are isolated from ~/Library and ~/.ssh; never used in production.
set -euo pipefail
[[ "$(uname -s)" == Darwin ]] || exit 0
app="dist/Warp SSH Manager.app"
if [[ ! -d "$app" ]]; then echo "No native app"; exit 0; fi
fixture="$RUNNER_TEMP/wsm-native-visual"
mkdir -p "$fixture/.ssh" "$fixture/data" dist
wsm="$app/Contents/MacOS/wsm"
export WSM_HOME="$fixture/data"
export WSM_SSH_CONFIG="$fixture/.ssh/config"
export WSM_WARP_CONFIG_DIR="$fixture/warp"
"$wsm" ui init
# Populate a reference-like, isolated UI fixture: different group counts,
# tag colors, a favorite star and enough cards to measure vertical rhythm.
for group in "生产环境" "测试环境" "开发环境" "数据库"; do
  "$wsm" ui add-group "$group"
done
for item in "vas-app-2:1622:api,production:生产环境:yes" "vas-app-1:22:api,production:生产环境:no" "vas-2:22:test:测试环境:no" "vas-smb-1:22:dev:开发环境:no" "db-1:22:database:数据库:no" "jump-server:22:ops:生产环境:no"; do
  IFS=: read -r name port tags group favorite <<< "$item"
  group_id="$("$wsm" ui snapshot | python3 -c 'import json,sys;g=sys.argv[1];print(next(x["id"] for x in json.load(sys.stdin)["groups"] if x["name"]==g))' "$group")"
  is_favorite=false
  [[ "$favorite" == yes ]] && is_favorite=true
  cat <<JSON | "$wsm" ui save >/dev/null
{"id":null,"name":"$name","alias":"$name","hostname":"192.0.2.42","username":"ubuntu","port":$port,"identity_file":null,"proxy_jump":null,"group_id":"$group_id","favorite":$is_favorite,"tags":"$tags","notes":"演示数据，仅用于自动化视觉验收"}
JSON
done
# GUI apps launched through Launch Services inherit launchd, not the shell.
launchctl setenv WSM_HOME "$WSM_HOME" || true
launchctl setenv WSM_SSH_CONFIG "$WSM_SSH_CONFIG" || true
launchctl setenv WSM_WARP_CONFIG_DIR "$WSM_WARP_CONFIG_DIR" || true
# Isolated screenshot fixture opens the connection tab for visual audit.
launchctl setenv WSM_CI_CONNECTION_INSPECTOR 1 || true
# GUI-only routing audit exercises quick-panel vs manager vs Dock reopen.
ROUTING_RESULT="$RUNNER_TEMP/wsm-native-window-routing.txt"
ROUTING_READY="$RUNNER_TEMP/wsm-native-quick-ready.txt"
rm -f "$ROUTING_RESULT" "$ROUTING_READY"
launchctl setenv WSM_WINDOW_ROUTING_SMOKE_RESULT "$ROUTING_RESULT" || true
launchctl setenv WSM_ROUTING_QUICK_READY "$ROUTING_READY" || true
# Hosted macOS runners may force Reduce Transparency on (we measured 1).
# Disable it only for the isolated runner's visual-regression process.
# This never touches a user's Mac or overrides the shipped app's accessibility.
ORIGINAL_REDUCE_TRANSPARENCY="$(defaults read com.apple.universalaccess reduceTransparency 2>/dev/null || echo unset)"
defaults write com.apple.universalaccess reduceTransparency -bool false || true
killall cfprefsd 2>/dev/null || true
sleep 2
echo "CI Reduce Transparency after override:"
defaults read com.apple.universalaccess reduceTransparency 2>/dev/null || true
BACKDROP_PID=""
cleanup_visual_fixture() {
  if [[ -n "$BACKDROP_PID" ]]; then kill "$BACKDROP_PID" 2>/dev/null || true; fi
  if [[ "$ORIGINAL_REDUCE_TRANSPARENCY" == "unset" ]]; then
    defaults delete com.apple.universalaccess reduceTransparency 2>/dev/null || true
  else
    defaults write com.apple.universalaccess reduceTransparency -bool "$([[ "$ORIGINAL_REDUCE_TRANSPARENCY" == "1" ]] && echo true || echo false)" || true
  fi
  launchctl unsetenv WSM_HOME 2>/dev/null || true
  launchctl unsetenv WSM_SSH_CONFIG 2>/dev/null || true
  launchctl unsetenv WSM_WARP_CONFIG_DIR 2>/dev/null || true
  launchctl unsetenv WSM_CI_CONNECTION_INSPECTOR 2>/dev/null || true
  launchctl unsetenv WSM_WINDOW_ROUTING_SMOKE_RESULT 2>/dev/null || true
  launchctl unsetenv WSM_ROUTING_QUICK_READY 2>/dev/null || true
}
trap cleanup_visual_fixture EXIT
# Set a CI *desktop* wallpaper to test behind-window vibrancy against
# blue/purple, as in the reference. This is NEVER drawn inside the app.
# Not all hosted macOS sessions permit desktop changes; remain best-effort.
CI_WALLPAPER="$RUNNER_TEMP/wsm-reference-desktop.png" xcrun swift - <<'SWIFT' >/dev/null 2>&1 || true
import AppKit
let wallpaper = NSImage(size:NSSize(width:1600,height:1000))
wallpaper.lockFocus()
let gradient = NSGradient(starting:NSColor(calibratedRed:0.53,green:0.72,blue:0.96,alpha:1),
                          ending:NSColor(calibratedRed:0.67,green:0.39,blue:0.79,alpha:1))
gradient?.draw(in:NSRect(x:0,y:0,width:1600,height:1000),angle:140)
wallpaper.unlockFocus()
if let tiff = wallpaper.tiffRepresentation,
   let png = NSBitmapImageRep(data:tiff)?.representation(using:.png,properties:[:]),
   let path = ProcessInfo.processInfo.environment["CI_WALLPAPER"] {
    let url=URL(fileURLWithPath:path)
    try? png.write(to:url)
    for screen in NSScreen.screens {
        try? NSWorkspace.shared.setDesktopImageURL(url,for:screen,options:[:])
    }
}
SWIFT
echo "macOS accessibility preference (best-effort):"
defaults read com.apple.universalaccess reduceTransparency 2>/dev/null || true
# A *separate* low-level macOS window provides a controlled backdrop.
# It is CI-only and never packaged into Warp SSH Manager. Unlike a synthetic
# app background it verifies NSVisualEffectView samples an actual other window.
WSM_CI_BACKDROP_STYLE=cool xcrun swift scripts/native-ci-backdrop.swift >"$RUNNER_TEMP/wsm-ci-backdrop.log" 2>&1 &
BACKDROP_PID=$!
sleep 4
if ! kill -0 "$BACKDROP_PID" 2>/dev/null; then
  echo "The CI wallpaper companion did not start; using system desktop"
  tail -n 20 "$RUNNER_TEMP/wsm-ci-backdrop.log" || true
  BACKDROP_PID=""
else
  echo "CI colored backdrop running behind the real app (pid $BACKDROP_PID)"
fi
# Prove the *companion window itself* is visible before examining any
# SSH app pixels. The previous A/B experiment saw no visual difference.
screencapture -x dist/native-ci-backdrop-cool-only.png 2>/dev/null || true
open -a "$PWD/$app" || { echo "GUI unavailable in runner"; exit 0; }
# Wait for the application's quick-launcher fixture, then capture the ACTUAL
# native floating panel from the runner shell before the app restores main.
for i in {1..24}; do
  [[ -s "$ROUTING_READY" ]] && break
  sleep 0.5
done
if [[ ! -s "$ROUTING_READY" ]]; then
  echo "FAILED: quick-panel fixture did not reach ready state"; exit 1
fi
quick_id="$(xcrun swift scripts/native-window-id.swift quick 2>/dev/null | tail -n 1 || true)"
if [[ "$quick_id" =~ ^[0-9]+$ ]]; then
  screencapture -x -l "$quick_id" dist/native-quick-panel.png 2>/dev/null || true
fi
screencapture -x dist/native-quick-panel-desktop.png 2>/dev/null || true
for i in {1..20}; do
  [[ -s "$ROUTING_RESULT" ]] && break
  sleep 0.5
done
# Fail CI if quick-panel and manager actions accidentally target the same window.
if [[ -s "$ROUTING_RESULT" ]]; then
  cp "$ROUTING_RESULT" dist/native-window-routing-audit.txt
  cat "$ROUTING_RESULT"
  grep -q 'PASS=true' "$ROUTING_RESULT" || {
    echo "FAILED: native Dock/menu window routing"; exit 1;
  }
else
  echo "FAILED: no window-routing audit from the native app"; exit 1
fi
# Exercise the OS-level app-open event instead of only calling the
# NSApplicationDelegate method. This reproduces the real Dock/reopen route.
# Hide and reopen 3 times, checking the on-screen WindowServer inventory.
: > dist/native-dock-window-count.txt
for attempt in 1 2 3; do
  osascript -e 'tell application "System Events" to set visible of first process whose name contains "Warp SSH" to false' 2>/dev/null || true
  sleep 1
  open -a "$PWD/$app"
  sleep 2
  echo "Dock/open event $attempt:" | tee -a dist/native-dock-window-count.txt
  xcrun swift scripts/native-manager-window-count.swift | tee -a dist/native-dock-window-count.txt
done
osascript -e 'tell application "System Events" to set frontmost of first process whose name contains "Warp SSH" to true' 2>/dev/null || true
sleep 2
window_id="$(xcrun swift scripts/native-window-id.swift 2>/dev/null | tail -n 1 || true)"
if [[ "$window_id" =~ ^[0-9]+$ ]]; then
  echo "Capturing complete window id $window_id"
  screencapture -x -l "$window_id" dist/native-macos-render.png 2>/dev/null || true
fi
if [[ ! -s dist/native-macos-render.png ]]; then
  # A fullscreen capture is useful as a diagnostic if WindowServer is missing.
  screencapture -x dist/native-macos-render.png 2>/dev/null || true
fi
# A/B proof of real behind-window sampling. Change the separate desktop
# window (not the SSH app), and capture the same app window again. If the
# window material is genuinely translucent, sampled pixels must respond.
screencapture -x dist/native-macos-desktop.png 2>/dev/null || true
if [[ "$window_id" =~ ^[0-9]+$ ]] && [[ -n "$BACKDROP_PID" ]]; then
  kill "$BACKDROP_PID" 2>/dev/null || true
  BACKDROP_PID=""
  WSM_CI_BACKDROP_STYLE=warm xcrun swift scripts/native-ci-backdrop.swift >"$RUNNER_TEMP/wsm-ci-warm-backdrop.log" 2>&1 &
  BACKDROP_PID=$!
  sleep 5
  osascript -e 'tell application "System Events" to set visible of first process whose name contains "Warp SSH" to false' 2>/dev/null || true
  sleep 2
  screencapture -x dist/native-ci-backdrop-warm-only.png 2>/dev/null || true
  osascript -e 'tell application "System Events" to set frontmost of first process whose name contains "Warp SSH" to true' 2>/dev/null || true
  sleep 2
  screencapture -x dist/native-macos-desktop-warm-with-app.png 2>/dev/null || true
  screencapture -x -l "$window_id" dist/native-macos-render-warm.png 2>/dev/null || true
  if [[ -s dist/native-macos-render-warm.png ]]; then
    echo "Captured identical real app against a second desktop backdrop"
  fi
fi
if [[ -s dist/native-macos-render.png ]]; then
  cp dist/native-macos-render.png dist/native-connection-inspector.png
  sips -g pixelWidth -g pixelHeight dist/native-macos-render.png
  echo "Captured actual SwiftUI rendering"
else
  echo "Runner does not provide a capturable login desktop; runtime screenshot must be checked on a Mac"
fi

# Window captures preserve alpha; verify no low-alpha columns or rows between panes.
if [[ -s dist/native-macos-render.png ]]; then
  xcrun swift scripts/native-window-seam-audit.swift \
    dist/native-macos-render.png \
    2>&1 | tee dist/native-window-seam-audit.txt
fi

# Window-only screencapture (-l) deliberately excludes the desktop composite,
# so comparing those images gives false zeros even when vibrancy works.
# Audit the actual full-desktop A/B frames to validate real backdrop sampling.
if [[ -s dist/native-macos-desktop.png && -s dist/native-macos-desktop-warm-with-app.png ]]; then
  xcrun swift scripts/native-backdrop-audit.swift \
    dist/native-macos-desktop.png \
    dist/native-macos-desktop-warm-with-app.png \
    2>&1 | tee dist/native-backdrop-audit.txt
fi
