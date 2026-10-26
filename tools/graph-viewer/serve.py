#!/usr/bin/env python3
"""Live viewer server for docs/tickets/graph.json (stdlib only).

Routes: GET / -> index.html, GET /graph.json (fresh read, no-store),
GET /events (Server-Sent Events: `event: change` when the file's mtime/size changes).
"""
import os
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))  # two levels up from this script
GRAPH = os.path.join(ROOT, "docs", "tickets", "graph.json")
INDEX = os.path.join(HERE, "index.html")
PORT = int(os.environ.get("GRAPH_VIEWER_PORT", "8731"))
POLL_S = 0.5
PING_S = 15.0


def stat_sig():
    try:
        st = os.stat(GRAPH)
        return (st.st_mtime, st.st_size)
    except OSError:
        return None


class Handler(BaseHTTPRequestHandler):
    server_version = "GraphViewer/1"

    def log_message(self, fmt, *args):  # silence default per-request logging
        pass

    def log_request(self, code="-", size="-"):
        # Only log non-200 responses (SSE/200s stay quiet).
        if str(code) != "200":
            sys.stderr.write("%s %s -> %s\n" % (self.command, self.path, code))
            sys.stderr.flush()

    def _send(self, code, body, ctype, extra=None):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        try:
            if path in ("/", "/index.html"):
                with open(INDEX, "rb") as f:
                    self._send(200, f.read(), "text/html; charset=utf-8")
            elif path == "/graph.json":
                try:
                    with open(GRAPH, "rb") as f:
                        data = f.read()
                    mtime = os.stat(GRAPH).st_mtime
                except OSError:
                    self._send(404, b'{"error":"graph.json not found"}', "application/json")
                    return
                self._send(200, data, "application/json", {"X-Graph-Mtime": "%.3f" % mtime})
            elif path == "/events":
                self._events()
            else:
                self._send(404, b"not found", "text/plain; charset=utf-8")
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            pass
        except OSError:
            pass

    def _events(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Connection", "keep-alive")
        self.send_header("X-Accel-Buffering", "no")
        self.end_headers()
        try:
            self.wfile.write(b"retry: 2000\n: connected\n\n")
            self.wfile.flush()
            last = stat_sig()
            last_ping = time.monotonic()
            while True:
                time.sleep(POLL_S)
                cur = stat_sig()
                now = time.monotonic()
                if cur != last:
                    last = cur
                    mt = cur[0] if cur else 0
                    self.wfile.write(("event: change\ndata: %.3f\n\n" % mt).encode())
                    self.wfile.flush()
                    last_ping = now
                elif now - last_ping >= PING_S:
                    self.wfile.write(b": ping\n\n")
                    self.wfile.flush()
                    last_ping = now
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError, OSError):
            pass  # client went away


class Server(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def handle_error(self, request, client_address):
        et = sys.exc_info()[0]
        if et and issubclass(et, (BrokenPipeError, ConnectionResetError, ConnectionAbortedError)):
            return
        super().handle_error(request, client_address)


def main():
    srv = Server(("127.0.0.1", PORT), Handler)
    sys.stderr.write("graph-viewer on http://127.0.0.1:%d (root %s)\n" % (PORT, ROOT))
    sys.stderr.flush()
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        srv.server_close()


if __name__ == "__main__":
    main()
