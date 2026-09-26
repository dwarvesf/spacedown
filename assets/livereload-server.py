#!/usr/bin/env python3
"""Minimal localhost live-reload server for md-preview --watch.

Serves the rendered HTML at ``/`` and the output file's mtime at ``/__mdp_version``,
bound to 127.0.0.1 on an ephemeral port. The watch-mode injected poll script
(assets/livereload-foot.html) fetches ``/__mdp_version`` every ~1s and reloads the page
when it changes; ``entr`` re-renders the HTML on each save, so the page tracks edits with
no manual refresh. Localhost-only, ephemeral port, no persistence: it lives and dies with
the --watch process. NOT a general server.

Usage: livereload-server.py <out.html> <port-file>
  Writes the chosen port to <port-file> (so the parent shell can read it), then serves
  forever until killed.
"""
import sys
import os
import http.server
import socketserver


def main():
    out_path = sys.argv[1]
    port_file = sys.argv[2]

    class Handler(http.server.BaseHTTPRequestHandler):
        def _send(self, body, ctype):
            self.send_response(200)
            self.send_header("Content-Type", ctype)
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            if self.path == "/__mdp_version":
                try:
                    v = repr(os.path.getmtime(out_path))
                except OSError:
                    v = "0"
                self._send(v.encode("utf-8"), "text/plain; charset=utf-8")
            elif self.path in ("/", "/index.html"):
                try:
                    with open(out_path, "rb") as f:
                        data = f.read()
                except OSError:
                    data = b"<!doctype html><meta charset=utf-8><body>rendering...</body>"
                self._send(data, "text/html; charset=utf-8")
            else:
                self.send_error(404)

        def log_message(self, *args):
            pass  # quiet: the parent logs the URL once

    # ephemeral port on localhost only
    httpd = socketserver.TCPServer(("127.0.0.1", 0), Handler)
    port = httpd.server_address[1]
    try:
        with open(port_file, "w") as f:
            f.write(str(port))
    except OSError:
        pass
    httpd.serve_forever()


if __name__ == "__main__":
    main()
