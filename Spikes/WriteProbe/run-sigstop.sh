#!/usr/bin/env bash
# run-sigstop.sh — SPK-010 / AC-078 write-path part (throwaway). Usage: run-sigstop.sh <bundle-id> <pid> [probe args...]
# Starts WriteProbe with a pause, SIGSTOPs the app mid-pause, waits for the probe, ALWAYS SIGCONTs (trap).
set -u
B="$1"; PID="$2"; shift 2
P="$(cd "$(dirname "$0")" && pwd)/.build/debug/WriteProbe"
trap 'kill -CONT "$PID" 2>/dev/null' EXIT INT TERM HUP
"$P" --bundle "$B" --pause-ms 1500 "$@" &
PP=$!
sleep 0.7
kill -STOP "$PID"; echo "# STOPPED $PID at $(TZ=America/Los_Angeles date '+%-I:%M:%S %p PT')"
wait "$PP"; echo "# probe rc=$?"
kill -CONT "$PID"; echo "# CONT $PID at $(TZ=America/Los_Angeles date '+%-I:%M:%S %p PT')"
