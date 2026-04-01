#!/usr/bin/env python3
"""Servidor HTTP sin COOP/COEP para que Firebase popups funcionen."""
import http.server
import socketserver
import os

DIRECTORY = os.path.join(os.path.dirname(__file__), "build", "web")
PORT = 5060

class NoCOOPHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

    def end_headers(self):
        # CORS permisivo
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "*")
        # Permitir embebido en iframes
        self.send_header("X-Frame-Options", "ALLOWALL")
        self.send_header("Content-Security-Policy", "frame-ancestors *")
        # NO enviamos Cross-Origin-Opener-Policy ni Cross-Origin-Embedder-Policy
        # para que los popups de Google Sign-In / Firebase funcionen correctamente
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(200)
        self.end_headers()

    def log_message(self, fmt, *args):
        pass  # silenciar logs


if __name__ == "__main__":
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("0.0.0.0", PORT), NoCOOPHandler) as httpd:
        print(f"Servidor activo en http://0.0.0.0:{PORT}")
        httpd.serve_forever()
