#!/usr/bin/env bash
# q.sh — run a command quietly.
# Prints only the last 60 lines (Q_LINES to change) of combined stdout+stderr, then the exit code.
# Exits with the command's own exit code. Full output is kept in $Q_LOG when set.
set -u
if [ $# -eq 0 ]; then
  echo "usage: scripts/q.sh <cmd> [args...]" >&2
  exit 64
fi
LINES="${Q_LINES:-60}"
tmp="$(mktemp -t q.XXXXXX)"
"$@" >"$tmp" 2>&1
code=$?
total=$(wc -l <"$tmp" | tr -d ' ')
if [ "$total" -gt "$LINES" ]; then
  echo "[q.sh] $total lines total; showing last $LINES"
fi
tail -n "$LINES" "$tmp"
echo "[q.sh] exit=$code"
if [ -n "${Q_LOG:-}" ]; then cp "$tmp" "$Q_LOG"; fi
rm -f "$tmp"
exit $code
