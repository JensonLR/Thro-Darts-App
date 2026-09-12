#!/usr/bin/env python3
"""The web app, served the way a deployment serves it: the pages and `/v1` on one origin.

THRØ's web client calls the API on its own origin by default, so a deployment can put Cloudflare in
front and route `/v1/*` to the API without the browser ever making a cross-origin request — no CORS,
no preflight, and no third host to configure. This mirrors that locally so what you look at in
development is arranged the way the real thing is.

    gradle -p services/api serve            # in another terminal, with PGHOST set
    python3 apps/web/serve.py               # then open http://localhost:8899
"""
import http.server
import os
import sys
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
API = os.environ.get("THRO_API", "http://localhost:8080")
PORT = int(os.environ.get("PORT", "8899"))


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=HERE, **kw)

    def do_GET(self):  # noqa: N802 - the base class names it
        if self.path.startswith("/v1/"):
            self.proxy()
        else:
            super().do_GET()

    def proxy(self):
        try:
            with urllib.request.urlopen(f"{API}{self.path}", timeout=20) as up:
                body, status = up.read(), up.status
        except urllib.error.HTTPError as e:
            body, status = e.read(), e.code
        except OSError as e:
            # Said rather than swallowed: a page showing "could not be read" while the reason was that
            # nothing is listening is the sort of thing that costs an hour.
            body = f'{{"error":"the API at {API} did not answer: {e}"}}'.encode()
            status = 502
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    print(f"THRØ web on http://localhost:{PORT}  (/v1 -> {API})", file=sys.stderr)
    http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
