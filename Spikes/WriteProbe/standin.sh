#!/usr/bin/env bash
# standin.sh — SPK-005 part 2 stand-in (throwaway). Packages the release WriteProbe binary as WriteProbe.app,
# signs it with "Zones Dev" and identifier com.dganesh.zones, then runs `--trust` as its own process via LaunchServices
# (a bare CLI run from a terminal inherits the terminal's Accessibility trust, which proves nothing).
# Build first:  scripts/q.sh swift build -c release --package-path Spikes/WriteProbe
# Usage: standin.sh            # package, sign, print requirement + trust
set -eu
D="$(cd "$(dirname "$0")" && pwd)"
APP="$D/.build/standin/WriteProbe.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
cp "$D/.build/release/WriteProbe" "$APP/Contents/MacOS/WriteProbe"
cat >"$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.dganesh.zones</string>
<key>CFBundleName</key><string>WriteProbe</string>
<key>CFBundleExecutable</key><string>WriteProbe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PL
codesign --force --sign "Zones Dev" --identifier com.dganesh.zones "$APP" 2>&1 | grep -v "replacing existing" || true
echo "requirement: $(codesign -d -r- "$APP" 2>&1 | grep designated)"
echo "cdhash count in requirement: $(codesign -d -r- "$APP" 2>&1 | grep -c cdhash || true)"
OUT="$(mktemp)"; open -W -n --stdout "$OUT" --stderr "$OUT" "$APP" --args --trust
echo "AXIsProcessTrusted as its own process: $(cat "$OUT")"; rm -f "$OUT"
