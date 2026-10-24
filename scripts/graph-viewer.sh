#!/usr/bin/env bash
# Live ticket-graph viewer: start | stop | status
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SERVE="$ROOT/tools/graph-viewer/serve.py"
PIDFILE=/tmp/zones-graph-viewer.pid
LOG=/tmp/zones-graph-viewer.log
PORT="${GRAPH_VIEWER_PORT:-8731}"
URL="http://127.0.0.1:$PORT/"

running() {
  [ -f "$PIDFILE" ] || return 1
  local pid; pid="$(cat "$PIDFILE" 2>/dev/null)"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

case "${1:-status}" in
  start)
    if running; then echo "already running (pid $(cat "$PIDFILE")): $URL"; exit 0; fi
    rm -f "$PIDFILE"
    GRAPH_VIEWER_PORT="$PORT" nohup python3 "$SERVE" >>"$LOG" 2>&1 &
    echo $! >"$PIDFILE"
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      sleep 0.3
      if ! kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        echo "failed to start; see $LOG" >&2; rm -f "$PIDFILE"; tail -n 5 "$LOG" >&2; exit 1
      fi
      if curl -s -o /dev/null "$URL"; then echo "started (pid $(cat "$PIDFILE")): $URL"; exit 0; fi
    done
    echo "started (pid $(cat "$PIDFILE")) but not answering yet: $URL"
    ;;
  stop)
    if running; then
      kill "$(cat "$PIDFILE")" 2>/dev/null; rm -f "$PIDFILE"; echo "stopped"
    else
      rm -f "$PIDFILE"; echo "not running"
    fi
    ;;
  status)
    if running; then echo "running (pid $(cat "$PIDFILE")): $URL"; else echo "not running"; exit 1; fi
    ;;
  *) echo "usage: $0 start|stop|status" >&2; exit 2 ;;
esac
