#!/usr/bin/env python3
"""
Servidor SPA para Flutter Web.
Redirige cualquier ruta desconocida a index.html (necesario para deep links).
"""
import http.server
import socketserver
import os
import mimetypes

PORT = 5060
WEB_DIR = os.path.dirname(os.path.abspath(__file__))

class SPAHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=WEB_DIR, **kwargs)

    def end_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, OPTIONS')
        self.send_header('X-Frame-Options', 'ALLOWALL')
        self.send_header('Content-Security-Policy', 'frame-ancestors *')
        super().end_headers()

    def do_GET(self):
        # Verificar si el archivo existe físicamente
        path = self.translate_path(self.path)
        
        # Si existe como archivo o directorio, servir normalmente
        if os.path.exists(path) and (os.path.isfile(path) or os.path.isdir(path)):
            super().do_GET()
            return

        # Cualquier ruta que no exista → servir index.html (SPA routing)
        self.path = '/index.html'
        super().do_GET()

    def log_message(self, format, *args):
        pass  # Silenciar logs

if __name__ == '__main__':
    os.chdir(WEB_DIR)
    with socketserver.TCPServer(('0.0.0.0', PORT), SPAHandler) as httpd:
        httpd.allow_reuse_address = True
        print(f'✅ SPA server en puerto {PORT}')
        httpd.serve_forever()
