#!/usr/bin/env bash
# PostToolUse hook: append the tool-result byte count to docs/tickets/<id>/spend.log (main checkout),
# update tokens_spent in graph.json (bytes/4), and emit CEILING when the agent passes its ceiling.
# Ticket id = ZONES_TICKET_ID, else from branch ticket/<id>, else "orchestrator".
# Ceiling = ZONES_AGENT_CEILING, else 200000 for orchestrator, 250000 for a ticket agent.
set -u
input="$(cat)"
bytes="$(printf '%s' "$input" | jq -c '.tool_response // empty' | wc -c | tr -d ' ')"
tool="$(printf '%s' "$input" | jq -r '.tool_name // "?"')"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"; cwd="${cwd:-$PWD}"
common="$(git -C "$cwd" rev-parse --git-common-dir 2>/dev/null)" || exit 0
case "$common" in /*) ;; *) common="$cwd/$common";; esac
main="$(cd "$(dirname "$common")" && pwd)"
branch="$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
id="${ZONES_TICKET_ID:-}"
if [ -z "$id" ]; then
  case "$branch" in ticket/*) id="${branch#ticket/}";; *) id="orchestrator";; esac
fi
dir="$main/docs/tickets/$id"; mkdir -p "$dir"
log="$dir/spend.log"
printf '%s %s %s\n' "$(date +%s)" "$tool" "$bytes" >>"$log"
read -r window cumulative <<<"$(awk '/^RESET/{s=0; next} {s+=$3; c+=$3} END{printf "%d %d", s/4, c/4}' "$log")"
ceiling="${ZONES_AGENT_CEILING:-}"
if [ -z "$ceiling" ]; then
  if [ "$id" = "orchestrator" ]; then ceiling=200000; else ceiling=250000; fi
fi
graph="$main/docs/tickets/graph.json"
if [ "$id" != "orchestrator" ] && [ -f "$graph" ]; then
  lock="$graph.lock"; i=0
  while ! mkdir "$lock" 2>/dev/null; do i=$((i+1)); [ $i -gt 50 ] && break; sleep 0.1; done
  tmp="$(mktemp)"
  if jq --arg id "$id" --argjson t "$cumulative" 'map(if .id==$id then .tokens_spent=$t else . end)' "$graph" >"$tmp" 2>/dev/null; then
    mv "$tmp" "$graph"
  else
    rm -f "$tmp"
  fi
  rmdir "$lock" 2>/dev/null
fi
if [ "$window" -ge "$ceiling" ]; then
  jq -n --arg m "CEILING: agent '$id' has spent ~$window tokens of tool results (ceiling $ceiling). Start no new slice. Append the ledger line, run the successor skill, and return a continuation object." \
    '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$m}}'
fi
exit 0
