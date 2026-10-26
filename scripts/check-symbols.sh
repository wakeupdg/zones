#!/usr/bin/env bash
# check-symbols.sh — AC-003 (symbols and plist), AC-002 and AC-013 (signature).
# Usage: scripts/check-symbols.sh [--signature | --runtime-only] [APP_OR_EXECUTABLE]
#   default target: the Debug build of the Zones scheme (xcodebuild -showBuildSettings).
#   A .app is checked for symbols and Info.plist keys; a bare Mach-O for symbols only.
#   --signature     also AC-002 (hardened runtime, no app-sandbox) and AC-013 (designated
#                   requirement: identifier com.dganesh.zones, a certificate term, no cdhash).
#   --runtime-only  only the AC-002 part (used by release.sh, where AC-013 does not apply).
# Exit 0 when every check passes, 1 naming the failing check, 2 on a usage problem.
#
# Resolved gap: public CoreGraphics functions such as CGSizeCreateDictionaryRepresentation start
# with "CGS" but are public API; names starting "CGSize" are excluded from the CGS rule.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

mode=""
target=""
while [ $# -gt 0 ]; do
  case "$1" in
    --signature) mode="signature" ;;
    --runtime-only) mode="runtime" ;;
    -*) echo "check-symbols: unknown flag $1" >&2; exit 2 ;;
    *) target="$1" ;;
  esac
  shift
done

if [ -z "$target" ]; then
  settings="$(cd "$here" && xcodebuild -project Zones.xcodeproj -scheme Zones -configuration Debug -showBuildSettings 2>/dev/null)"
  dir="$(echo "$settings" | sed -n 's/^ *BUILT_PRODUCTS_DIR = //p' | head -1)"
  prod="$(echo "$settings" | sed -n 's/^ *FULL_PRODUCT_NAME = //p' | head -1)"
  if [ -z "$dir" ] || [ -z "$prod" ]; then
    echo "check-symbols: cannot resolve the Debug build; pass a path" >&2
    exit 2
  fi
  target="$dir/$prod"
fi
if [ ! -e "$target" ]; then
  echo "check-symbols: no such path: $target" >&2
  exit 2
fi

app=""
exe="$target"
case "$target" in
  *.app)
    app="${target%/}"
    name="$(plutil -extract CFBundleExecutable raw -o - "$app/Contents/Info.plist" 2>/dev/null || true)"
    if [ -n "$name" ] && [ -f "$app/Contents/MacOS/$name" ]; then
      exe="$app/Contents/MacOS/$name"
    else
      exe="$(find "$app/Contents/MacOS" -type f | head -1)"
    fi
    ;;
esac
if [ -n "$mode" ] && [ -z "$app" ]; then
  echo "check-symbols: --signature needs a .app" >&2
  exit 2
fi

fail=0

# 1. forbidden undefined symbols
forbidden='CGRequestScreenCaptureAccess CGPreflightScreenCaptureAccess CGPreflightListenEventAccess CGRequestListenEventAccess IOHIDRequestAccess IOHIDCheckAccess'
offenders=""
while IFS= read -r line; do
  sym="${line##* }"
  sym="${sym#_}"
  [ -z "$sym" ] && continue
  hit=0
  for f in $forbidden; do [ "$sym" = "$f" ] && hit=1; done
  case "$sym" in
    SLS*) hit=1 ;;
    CGSize*) ;;
    CGS*) hit=1 ;;
  esac
  [ "$hit" -eq 1 ] && offenders="$offenders$sym"$'\n'
done < <(nm -u "$exe" 2>/dev/null)
if [ -n "$offenders" ]; then
  echo "forbidden symbols:"
  printf '%s' "$offenders" | sort -u
  fail=1
fi

# 2. Info.plist keys (apps only)
if [ -n "$app" ]; then
  plist="$(plutil -p "$app/Contents/Info.plist" 2>/dev/null || true)"
  for key in NSScreenCaptureUsageDescription NSInputMonitoringUsageDescription; do
    if echo "$plist" | grep -q "$key"; then
      echo "forbidden Info.plist key: $key"
      fail=1
    fi
  done
fi

# 3. signature checks
if [ -n "$mode" ]; then
  sig="$(codesign -dv --entitlements :- "$app" 2>&1)"
  flags="$(echo "$sig" | sed -n 's/.*flags=0x[0-9a-fA-F]*(\([^)]*\)).*/\1/p' | head -1)"
  case ",$flags," in
    *,runtime,*) ;;
    *) echo "AC-002 failed: hardened runtime flag missing (flags=($flags))"; fail=1 ;;
  esac
  if echo "$sig" | grep -q 'com.apple.security.app-sandbox'; then
    echo "AC-002 failed: app-sandbox entitlement present"
    fail=1
  fi
  if [ "$mode" = "signature" ]; then
    req="$(codesign -d -r- "$app" 2>&1)"
    echo "$req" | grep -q 'identifier "com.dganesh.zones"' || { echo "AC-013 failed: identifier com.dganesh.zones not in requirement"; fail=1; }
    echo "$req" | grep -q 'certificate' || { echo "AC-013 failed: requirement has no certificate term"; fail=1; }
    if echo "$req" | grep -q 'cdhash'; then echo "AC-013 failed: requirement contains cdhash"; fail=1; fi
    devhash="$(security find-identity -p codesigning 2>/dev/null | sed -n 's/^ *[0-9]*) \([0-9A-Fa-f]\{40\}\) "Zones Dev".*/\1/p' | head -1)"
    if [ -n "$devhash" ]; then
      want="$(echo "$devhash" | tr 'a-f' 'A-F')"
      have="$(echo "$req" | sed -n 's/.*H"\([0-9A-Fa-f]*\)".*/\1/p' | head -1 | tr 'a-f' 'A-F')"
      if [ "$want" != "$have" ]; then
        echo "AC-013 failed: requirement certificate hash ($have) is not the Zones Dev hash ($want)"
        fail=1
      fi
    fi
  fi
fi

if [ "$fail" -ne 0 ]; then exit 1; fi
echo "symbols: ok"
exit 0
