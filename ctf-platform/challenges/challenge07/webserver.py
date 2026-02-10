#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, HTTPServer

TOKEN = "token-07-http"


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.headers.get("X-CTF-Key") == "open-sesame":
            body = TOKEN.encode("utf-8")
            self.send_response(200)
        else:
            body = b"missing header"
            self.send_response(403)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    server = HTTPServer(("0.0.0.0", 8080), Handler)
    server.serve_forever()
