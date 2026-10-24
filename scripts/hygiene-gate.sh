#!/usr/bin/env bash
# hygiene-gate.sh — AC-162. Scans ROOT/App/**/*.swift (default: repo root) and prints
#   unsafe-ops: N / ax-imports: N / cgwindowlist-uses: N
# Exit 1 if any count is non-zero, 2 when ROOT/App is missing.
# Sources/ZonesWindowing/Adapters and Seams are never scanned: that is the exemption.
# Lines are counted strictly, comments included. A line with the zones:allow marker is exempt
# from the unsafe-ops class only.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
root="${1:-$here}"
if [ ! -d "$root/App" ]; then
  echo "hygiene-gate: no App/ directory under $root" >&2
  exit 2
fi
files=()
while IFS= read -r f; do files+=("$f"); done < <(find "$root/App" -type f -name '*.swift' | sort)

count() { # count <grep -E pattern> [exclude-marker]
  local pattern="$1" exclude="${2:-}" n=0
  if [ "${#files[@]}" -gt 0 ]; then
    if [ -n "$exclude" ]; then
      n=$(cat "${files[@]}" | { grep -E "$pattern" || true; } | { grep -v "$exclude" || true; } | wc -l)
    else
      n=$(cat "${files[@]}" | { grep -E "$pattern" || true; } | wc -l)
    fi
  fi
  echo "$n" | tr -d ' '
}

unsafe=$(count 'try!|(^|[^A-Za-z0-9_])as!|fatalError\(' 'zones:allow')
ax=$(count '^[[:space:]]*import[[:space:]]+ApplicationServices')
cgw=$(count 'CGWindowList')
echo "unsafe-ops: $unsafe"
echo "ax-imports: $ax"
echo "cgwindowlist-uses: $cgw"
if [ "$unsafe" -gt 0 ] || [ "$ax" -gt 0 ] || [ "$cgw" -gt 0 ]; then exit 1; fi
exit 0
