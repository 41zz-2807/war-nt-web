# Warnet Billing System

Sistem billing warnet lengkap: manajemen PC, billing per menit/jam/nominal/member,
voucher, tutup hari, dan agen client di PC warnet. Backend Node.js + PostgreSQL +
Redis, dashboard web grid kartu PC, container simulasi PC client untuk dev, dan
agen client Windows (.NET 8).

## Arsitektur

- **`server/`** — Backend Express + Socket.IO + PostgreSQL. Skema & seed dibuat
  otomatis di `src/db.ts`.
- **`web/`** — Dashboard web statis (HTML/CSS/JS) disajikan Node static server
  di container (`web/server.js`, tanpa nginx/reverse proxy). Halaman utama:
  `public/index.html` (grid kartu PC ala warnet, dengan tombol **Config** untuk
  membuat `install.config` installer PC client).
- **`simulator/`** — Container dev yang mensimulasikan banyak PC client
  (polling `/api/pcs`, konek WebSocket dengan token tiap PC). `SIM_MAX=30`.
- **`client-net/`** — Agen client Windows (.NET 8): `Program.cs` (Socket.IO +
  token auth), `Watchdog.cs` (hardening + TLS pinning). Installer di
  `client-net/installer/`.

## Menjalankan (wajib Docker)

```bash
docker compose up -d --build     # postgres, redis, server, web, simulator
docker compose ps                 # 5 container aktif
```

- Web: `http://localhost:5173`
- API: `http://localhost:3000`
- Login: `admin`/`admin123` atau `kasir`/`admin123`

> Jangan jalankan build di host — Node.js host rusak (ICU dyld). Semua build
> lewat Docker.

## Fitur

- Billing: nominal (min Rp1.000 kelipatan Rp500 → Rp3.000/jam), per jam, durasi,
  atau saldo member.
- Voucher: kode 6 digit, berlaku 90 hari, auto-expire & revoke manual.
- Member: password 4 digit, top-up, saldo menit.
- Tutup hari: rekap kas per jenis transaksi, menutup semua sesi aktif.
- PC client online/offline real-time (heartbeat, token auth via WebSocket).
- Uninstall agent diamankan OTP via Telegram (opsional, mode dev bila nonaktif).

## Dokumentasi

- `AGENTS.md` — struktur proyek, konvensi koding, aturan billing, panduan cepat.
- `PRODUCTION.md` — panduan go-live produksi (deploy, keamanan, firewall, backup,
  SOP, troubleshooting).
- `client-net/installer/README-CLIENT.md` — panduan build & instal agen Windows.

## Produksi

- `docker-compose.prod.yml` — komposisi produksi TANPA simulator. Butuh `.env`
  dari `.env.prod.example` (`POSTGRES_PASSWORD` wajib).
- `deploy/backup.sh` — backup Postgres (dump+gzip, retensi 14 hari, cron disarankan).
- Peta port produksi: `5173` dashboard, `3000` API + WebSocket, tanpa reverse proxy.
- Sebelum go-live: ganti password default admin/kasir (lihat `PRODUCTION.md` §4.2).