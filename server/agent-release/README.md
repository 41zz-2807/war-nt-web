# Folder hasil build agen client Windows, disajikan server ke PC client
# via HTTP untuk "online installer" (installer sekali klik dari dashboard).

Letakkan file berikut di folder ini (hasil `client-net/installer/build-windows.ps1`):

    billing-client-release.zip

Cara: di mesin Windows dengan .NET 8 SDK, jalankan
`client-net/installer/build-windows.ps1` — script itu otomatis membuat zip ini.

Setelah ditaruh, server menyajikannya di:
    http://<IP-SERVER>:3000/agent/billing-client-release.zip
Cek: http://localhost:3000/api/installer/status  -> release_ready: true

Folder ini ter-mount sebagai volume di container server (tidak perlu rebuild
image, cukup letakkan zip lalu `docker compose restart server`).