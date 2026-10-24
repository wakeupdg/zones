#!/usr/bin/env bash
# graph-set.sh — set fields of one ticket in docs/tickets/graph.json (main checkout), under a lock.
# Usage: scripts/graph-set.sh <id> <state> [last_report text]
#   state in todo|building|review|merging|done|blocked-needs-human
# Sets branch to ticket/<id> when state leaves todo. Works from any worktree.
set -euo pipefail
id="$1"; state="$2"; report="${3:-}"
case "$state" in todo|building|review|merging|done|blocked-needs-human) ;; *) echo "bad state $state" >&2; exit 64;; esac
common="$(git rev-parse --git-common-dir)"; case "$common" in /*) ;; *) common="$PWD/$common";; esac
main="$(cd "$(dirname "$common")" && pwd)"
graph="${ZONES_GRAPH:-$main/docs/tickets/graph.json}"
lock="$graph.lock"; i=0
while ! mkdir "$lock" 2>/dev/null; do i=$((i+1)); [ $i -gt 100 ] && { echo "lock timeout" >&2; exit 1; }; sleep 0.1; done
trap 'rmdir "$lock" 2>/dev/null' EXIT
jq -e --arg id "$id" 'map(select(.id==$id)) | length == 1' "$graph" >/dev/null || { echo "unknown ticket $id" >&2; exit 1; }
tmp="$(mktemp)"
jq --arg id "$id" --arg st "$state" --arg rep "$report" '
  map(if .id==$id then
        .state=$st
        | (if $st!="todo" then .branch=("ticket/"+$id) else . end)
        | (if $rep!="" then .last_report=$rep else . end)
      else . end)' "$graph" >"$tmp" && mv "$tmp" "$graph"
echo "$id -> $state"
