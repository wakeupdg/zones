#!/usr/bin/env bash
# ticket-lint.sh — AC-167. Checks the protocol, fake and tests fields of every ticket in a graph file.
# Usage: scripts/ticket-lint.sh [GRAPH]   (default docs/tickets/graph.json)
# A field is missing when absent, not a string, empty or whitespace-only. `tests` may not be "none"
# (case-insensitive after trim). Exit 0 clean, 1 on missing fields, 2 on an unusable file.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
graph="${1:-$here/docs/tickets/graph.json}"
if ! command -v jq >/dev/null 2>&1; then
  echo "ticket-lint: jq is required" >&2
  exit 2
fi
if [ ! -f "$graph" ]; then
  echo "ticket-lint: no such file: $graph" >&2
  exit 2
fi
if [ "$(jq -r 'if type == "array" then "array" else "other" end' "$graph" 2>/dev/null || echo bad)" != "array" ]; then
  echo "ticket-lint: $graph is not a JSON array" >&2
  exit 2
fi
report="$(jq -r '
  def blank: (type != "string") or (gsub("^\\s+|\\s+$"; "") == "");
  def nonetests: (type == "string") and (gsub("^\\s+|\\s+$"; "") | ascii_downcase) == "none";
  [ .[]
    | { id: (.id // "?"),
        bad: ( [ (if (.protocol | blank) then "protocol" else empty end),
                 (if (.fake | blank) then "fake" else empty end),
                 (if ((.tests | blank) or (.tests | nonetests)) then "tests" else empty end) ] ) } ] as $rows
  | "tickets: \($rows | length), missing-fields: \([$rows[] | select(.bad | length > 0)] | length)",
    ( $rows[] | select(.bad | length > 0) | "FAIL \(.id): \(.bad | join(", "))" )
' "$graph")"
echo "$report"
if [ "$(echo "$report" | wc -l | tr -d ' ')" -gt 1 ]; then exit 1; fi
exit 0
