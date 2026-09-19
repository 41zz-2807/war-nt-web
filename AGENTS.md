# AGENTS.md

## Project
Warnet Billing System — sistem billing warnet lengkap: manajemen PC, billing per
menit/jam/nominal/member, voucher, tutup hari, dan agen client di PC warnet.
Terdiri atas backend (Node.js + PostgreSQL + Redis), dashboard web, container
simulasi PC client, dan agen client Windows (.NET).

## Struktur
- `server/` — Backend Node.js (Express + Socket.IO + PostgreSQL). Berisi `src/index.ts`, `src/db.ts`, `tools/client-simulator.js`, Dockerfile.
- `web/` — Dashboard web (HTML/CSS/JS statis disajikan Node static server di container, `web/server.js`). Halaman utama: `public/index.html` (grid kartu PC ala warnet).
- `simulator/` — Container Node yang mensimulasikan banyak PC client sekaligus (polling `/api/pcs`, konek WebSocket dengan token tiap PC). `SIM_MAX=30` di compose.
- `client-net/` — Agen client Windows (.NET 8): `Program.cs` (WebSocket Socket.IO + auth token), `Watchdog.cs` (kunci Task Manager/RegEdit/CMD, TLS pinning). Instalasi: `client-net/installer/`.

## Cara menjalankan (wajib Docker — host Node.js rusak: ICU dyld error)
```bash
docker compose up -d --build        # bangun ulang & mulai (postgres, redis, server, web)
docker compose ps                     # cek 4 container aktif
# Simulator = profile opsional, default NONAKTIF (agar PC baru tidak otomatis online).
# Nyalakan hanya saat butuh: docker compose --profile simulator up -d
```
- Web: `http://localhost:5173` (mapped `5173:80`)
- API: `http://localhost:3000`
- Login: `admin`/`admin123` atau `kasir`/`admin123`
- HANYA build/serve lewat Docker. Jangan jalankan `npm run build` langsung di host (ICU >64 pecah).

## Aturan billing (penting — validasi harus sesuai)
- Nominal: bilangan bulat >= 1000 dan kelipatan 500, baik voucher maupun top-up member.
- Tarif: Rp1.000 = 20 menit → Rp3.000/jam.
- Voucher: kode 6 digit, kedaluwarsa 90 hari (auto-revoke saat ambil riwayat), bisa revoke manual.
- Member: password persis 4 digit (numerik).
- PC client konek via WebSocket, auth `{auth:{token}}` (token di kolom `pcs.token`).
  Dashboard web konek dengan `{auth:{web:true}}`.
- Online = heartbeat tiap 20 detik; server menandai offline bila last_seen > 45 detik.

## DB
- Skema + seed dibuat otomatis oleh `server/src/db.ts` (pg Pool, CREATE TABLE IF NOT EXISTS).
- Perubahan skema TIDAK otomatis menyesuaikan tabel lama → perlu `DROP TABLE` manual di database.
- Kotak-kotak: `users`, `pcs`, `vouchers`, `members`, `billing_sessions`, `transactions`, `tutup_hari`, `audit_log`.

## Cek cepat end-to-end
```bash
curl -s http://localhost:3000/api/pcs | python3 -m json.tool     # online=? tiap PC
docker logs billing-simulator | tail                            # PC konek otomatis
curl -s -X POST http://localhost:3000/api/billing/start \
  -H "Content-Type: application/json" -d '{"pc_id":1,"amount":3000}'
```

## Client Windows & installer
- Sumber: `client-net/` — target `net8.0`, dep `System.Configuration.ConfigurationManager`.
- Build Windows: `client-net/installer/build-windows.ps1` → `dotnet publish -r win-x64`.
- Paket `.exe`: `WarnetClientSetup.iss` (Inno Setup). Tanpa Inno: `install-silent.bat` (baca `install.config`).
- Di dashboard web, tiap kartu PC punya tombol **Config** → modal berisi
  ServerUrl (terdeteksi otomatis dari host yang dibuka kasir), Token PC, PCName.
  Dua opsi hasil: (1) **Download Instal Otomatis (.bat)** = online installer
  sekali klik — agen diunduh dari `http://IP:3000/agent/billing-client-release.zip`;
  (2) **download/copy `install.config`** untuk instal manual flashdisk.
- Server menyajikan folder `server/agent-release/` secara statis di `/agent`
  (volume-mounted), dibuat `build-windows.ps1`; cek `GET /api/installer/status`.
- Instal membuat: folder di `Program Files`, task terjadwal saat logon, registry hardening
  (DisableTaskMgr/NoRun/DisableRegistryTools/DisableCMD), uninstaller membaliknya.
- Uninstall diminta **OTP dari Telegram**: server kirim kode 6 digit (5 menit,
  1x pakai, rate-limit 1/menit/PC) bila `TELEGRAM_BOT_TOKEN`+`TELEGRAM_ADMIN_CHAT_ID`
  terisi; bila kosong → mode dev (`dev_code` di respon) dan uninstall tetap jalan.
  Endpoint: `/api/otp/status|request|verify`, tabel `otp_codes`.

## Konvensi
- API endpoint berada di bawah `/api/...`.
- Web UI memilih base API: `const API = location.port === '5173' ? 'http://localhost:3000' : location.origin;`
- Container simulator memakai `SERVER_URL=http://server:3000` (nama service, bukan localhost).
- Bahasa: Indonesian (console/UI/komentar) kecuali nama kode.

## Produksi
- `PRODUCTION.md` = panduan go-live (deploy, keamanan, firewall, backup, SOP, troubleshooting).
- `docker-compose.prod.yml` = komposisi produksi TANPA simulator; butuh `.env`
  dari `.env.prod.example` (`POSTGRES_PASSWORD` wajib, guard aktif bila kosong).
- `deploy/backup.sh` = dump+gzip Postgres (cron disarankan). Tanpa reverse proxy:
  dashboard `:5173` + API/WS `:3000` terpisah.
- Sebelum produksi: ganti password default admin/kasir (§4.2) dan terapkan
  perbaikan base-API LAN di `web/public/index.html` (§3.4) — default dev
  `localhost:3000` TIDAK cocok saat dashboard dibuka dari PC lain di LAN.