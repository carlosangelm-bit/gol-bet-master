#!/bin/bash
# post_build.sh — Ejecutar después de: flutter build web --release --pwa-strategy=none
# Restaura el SW de limpieza
BUILD_DIR="$(dirname "$0")/../build/web"
echo "[post_build] Restaurando flutter_service_worker.js..."
cat > "$BUILD_DIR/flutter_service_worker.js" << 'SWEOF'
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', async () => {
  const keys = await caches.keys();
  await Promise.all(keys.map(k => caches.delete(k)));
  self.registration.unregister();
  self.clients.claim();
});
SWEOF
echo "[post_build] ✓ Listo para deploy"
