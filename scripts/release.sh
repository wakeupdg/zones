#!/usr/bin/env bash
# release.sh — universal Zones.app build, signing decision, notarization, DMG.
# Usage: scripts/release.sh [--dry-run]   (run from any cwd)
#
# Environment:
#   ZONES_SIGN_IDENTITY   Developer ID identity; unset means ad-hoc signing (one stderr warning).
#   ZONES_NOTARY_PROFILE  notarytool keychain profile; unset skips notarization.
#   ZONES_RELEASE_SKIP_BUILD=1  test hook: steps 1 to 4 print "skipped (test hook)" so
#                         GateScriptTests stays fast and hermetic. Never set it for a real release.
#
# --dry-run performs every step except signing, notarization and DMG creation, prints the
# signing decision, and exits 0 (ADR-0025 amendment, AC-014). It never calls codesign,
# notarytool, stapler or hdiutil.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
root="$(pwd)"

dry=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) dry=1 ;;
    *) echo "usage: scripts/release.sh [--dry-run]" >&2; exit 64 ;;
  esac
done

version="$(sed -n 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"\{0,1\}\([^"[:space:]]*\)"\{0,1\}.*$/\1/p' project.yml | head -1)"
version="${version:-0.1.0}"
derived="DerivedData/release"
app="$derived/Build/Products/Release/Zones.app"
identity="${ZONES_SIGN_IDENTITY:-}"
skip="${ZONES_RELEASE_SKIP_BUILD:-}"
mkdir -p "$derived"

if [ -n "$skip" ]; then
  echo "[release] step 1: xcodegen generate: skipped (test hook)"
  echo "[release] step 2: release build: skipped (test hook)"
  echo "[release] step 3: universal check: skipped (test hook)"
  echo "[release] step 4: check-symbols: skipped (test hook)"
else
  echo "[release] step 1: xcodegen generate"
  xcodegen generate >"$derived/xcodegen.log" 2>&1 || { tail -20 "$derived/xcodegen.log"; exit 1; }

  echo "[release] step 2: release build (arm64 + x86_64)"
  if ! xcodebuild -quiet -project Zones.xcodeproj -scheme Zones -configuration Release \
      -derivedDataPath "$derived" ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
      CODE_SIGNING_ALLOWED=NO build >"$derived/build.log" 2>&1; then
    tail -20 "$derived/build.log"
    exit 1
  fi

  echo "[release] step 3: universal check"
  exe="$app/Contents/MacOS/Zones"
  archs="$(lipo -archs "$exe")"
  case " $archs " in
    *" arm64 "*) ;;
    *) echo "[release] missing arm64 slice (have: $archs)"; exit 1 ;;
  esac
  case " $archs " in
    *" x86_64 "*) ;;
    *) echo "[release] missing x86_64 slice (have: $archs)"; exit 1 ;;
  esac
  echo "[release] archs: $archs"

  echo "[release] step 4: check-symbols"
  scripts/check-symbols.sh "$app"
fi

echo "[release] step 5: signing decision"
if [ -n "$identity" ]; then
  echo "[release] signing: $identity (Developer ID)"
else
  echo "[release] signing: ad-hoc"
  echo "[release] WARNING: ZONES_SIGN_IDENTITY not set; signing ad-hoc (not notarizable, Gatekeeper will warn)" >&2
fi

if [ "$dry" -eq 1 ]; then
  echo "[release] dry-run: skipped signing, notarization, dmg"
  exit 0
fi

echo "[release] step 6: sign"
if [ -n "$identity" ]; then
  codesign --force --options runtime --timestamp --entitlements App/Zones.entitlements \
    --sign "$identity" "$app"
else
  codesign --force --options runtime --entitlements App/Zones.entitlements --sign - "$app"
fi
codesign --verify --strict "$app"
scripts/check-symbols.sh --runtime-only "$app"

echo "[release] step 7: notarize"
if [ -z "$identity" ]; then
  echo "[release] notarization skipped: ad-hoc signature cannot be notarized"
elif [ -z "${ZONES_NOTARY_PROFILE:-}" ]; then
  echo "[release] notarization skipped: ZONES_NOTARY_PROFILE not set"
else
  zip="$derived/Zones-notarize.zip"
  ditto -c -k --keepParent "$app" "$zip"
  xcrun notarytool submit "$zip" --keychain-profile "$ZONES_NOTARY_PROFILE" --wait
  xcrun stapler staple "$app"
fi

echo "[release] step 8: dmg"
mkdir -p dist
staging="$derived/dmg-staging"
rm -rf "$staging"
mkdir -p "$staging"
cp -R "$app" "$staging/Zones.app"
ln -s /Applications "$staging/Applications"
dmg="dist/Zones-$version.dmg"
hdiutil create -volname Zones -srcfolder "$staging" -ov -format UDZO "$dmg" >/dev/null
echo "[release] wrote $dmg"
echo "sha256 \"$(shasum -a 256 "$dmg" | awk '{print $1}')\""
