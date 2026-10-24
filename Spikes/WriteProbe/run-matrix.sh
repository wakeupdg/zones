#!/usr/bin/env bash
# run-matrix.sh — SPK-010 matrix driver (throwaway). Usage: run-matrix.sh <bundle-id> <logfile>
# Pass A: toggle x10. Pass B: leave x10. Pass C: toggle x10 with AXEnhancedUserInterface seeded true (VO-off stand-in).
# VoiceOver-on passes are human-only and are NOT run here.
set -u
P="$(cd "$(dirname "$0")" && pwd)/.build/debug/WriteProbe"
B="$1"; LOG="$2"
T="${TARGET:-120,120,900,600}"
{
  echo "## $B"
  for pass in "A toggle" "B leave" "C toggle --seed-eui"; do
    pol="$(echo "$pass" | cut -d' ' -f2)"; extra="$(echo "$pass" | cut -d' ' -f3-)"
    echo "# pass $pass"
    # shellcheck disable=SC2086
    "$P" --bundle "$B" --target "$T" --policy "$pol" --runs 10 --json $extra 2>&1
    echo "# rc=$?"
  done
} >>"$LOG"
