#!/usr/bin/env bash
# agent-state.sh — print current branch, ticket id, ledger tail, tokens_spent.
# Usage: scripts/agent-state.sh [--reset]   (--reset starts a new spend window for this agent)
set -u
root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "[agent-state] not a git repo"; exit 0; }
common="$(git rev-parse --git-common-dir 2>/dev/null)"
case "$common" in /*) ;; *) common="$PWD/$common";; esac
main="$(cd "$(dirname "$common")" && pwd)"
branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo detached)"
id="${ZONES_TICKET_ID:-}"
if [ -z "$id" ]; then
  case "$branch" in ticket/*) id="${branch#ticket/}";; *) id="orchestrator";; esac
fi
spend="$main/docs/tickets/$id/spend.log"
if [ "${1:-}" = "--reset" ]; then
  mkdir -p "$(dirname "$spend")"
  printf 'RESET %s\n' "$(date +%s)" >>"$spend"
  echo "[agent-state] spend window reset for $id"
fi
echo "branch: $branch"
echo "ticket: $id"
echo "worktree: $root"
if [ "$id" = "orchestrator" ]; then
  ledger="$root/docs/ORCHESTRATOR-LEDGER.md"
else
  ledger="$root/docs/tickets/$id/ledger.md"
fi
if [ -f "$ledger" ]; then
  echo "ledger tail ($ledger):"
  tail -n 10 "$ledger" | sed 's/^/  /'
else
  echo "ledger: none yet ($ledger)"
fi
graph="$main/docs/tickets/graph.json"
if [ "$id" != "orchestrator" ] && [ -f "$graph" ]; then
  ts="$(jq -r --arg id "$id" '.[] | select(.id==$id) | .tokens_spent // 0' "$graph" 2>/dev/null)"
  echo "tokens_spent (graph.json): ${ts:-n/a}"
fi
if [ -f "$spend" ]; then
  awk '/^RESET/{s=0; next} {s+=$3; c+=$3} END{printf "tokens this window: ~%d  (cumulative ~%d)\n", s/4, c/4}' "$spend"
else
  echo "tokens this window: 0"
fi
