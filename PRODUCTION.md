# Warnet Billing System — Panduan Produksi

Dokumen ini memandu pemasangan, pengamanan, dan operasional sistem billing warnet
di lingkungan produksi (LAN warnet). Baca `AGENTS.md` untuk struktur proyek dan
konvensi koding; baca `client-net/installer/README-CLIENT.md` untuk sisi PC client.

---

## 1. Ringkasan: Dev vs Produksi

| Aspek          | Dev / Simulasi                                  | Produksi                                                   |
|----------------|-------------------------------------------------|------------------------------------------------------------|
| Container      | postgres, redis, server, web, **simulator**     | postgres, redis, server, web (simulator **dihapus**)       |
| PC            | `simulator/` = banyak PC virtual                | Agen Windows (`client-net/`) di tiap PC fisik              |
| Kredensial     | nilai default (`admin123`, `billing_pass`)      | password kuat + token JWT tidak dipakai publik             |
| Akses network  | bebas di mesin dev                              | LAN warnet + firewall; port DB/Redis tertutup              |

> Diagram produksi:

```
  PC Client (Windows — agen client-net)
        |  WebSocket ws://SERVER:3000/socket.io/  (auth token tiap PC)
        v
  +------------------------------------------------+
  |  billing-server  (Express + Socket.IO, :3000)  |
  |   billing-web    (Node static server, :5173)   |
  |   billing-postgres (:5432, internal)           |
  |   billing-redis   (:6379, internal)            |
  +------------------------------------------------+
        ^
  Kasir / Admin — browser http://SERVER-IP:5173
```

---

## 2. Prasyarat Server

- Sistem operasi: Linux (disarankan Ubuntu 22+/Debian 12), atau Windows/macOS
  dengan Docker Desktop — **recommendasi: Linux**.
- Docker Engine 24+ dan Docker Compose v2.
- IP LAN statis (mis. `192.168.1.10`) — jangan pakai DHCP agar token/URL client stabil.
- Ruang disk cukup untuk volume Postgres + backup (rekomendasi ≥ 10 GB).
- Node.js di host HANYA diperlukan untuk build agen Windows (pakai mesin lain).
  Server cukup Docker (semua di-container).

---

## 3. Langkah Deploy

### 3.1 Siapkan environment

```bash
cp .env.prod.example .env
nano .env        # isi POSTGRES_PASSWORD kuat + ganti nilai lain
```

`.env.prod.example` wajib diedit minimal:
- `POSTGRES_PASSWORD` — password database, harus kuat.
- (Opsional) ubah `POSTGRES_USER`, `POSTGRES_DB`.

### 3.2 Bangun dan jalankan komposisi produksi

```bash
docker compose -f docker-compose.prod.yml up -d --build
docker compose -f docker-compose.prod.yml ps
```

Harus muncul 4 container: `billing-postgres`, `billing-redis`,
`billing-server`, `billing-web`. Simulator TIDAK ada di produksi.

### 3.3 Verifikasi kesehatan

```bash
curl -s http://localhost:3000/health                 # {"status":"ok",...}
curl -s -X POST http://localhost:3000/api/auth/login \
  -H "Content-Type: application/json" -d '{"username":"admin","password":"admin123"}'
```

Login pertama memakai `admin`/`admin123` (di-seed otomatis saat DB kosong).
**Segera ganti password — lihat §4.2.**

### 3.4 Buka dashboard

`http://SERVER-IP:5173` — login `admin`/`admin123`.

> Base API dashboard otomatis benar di LAN: kode memakai
> `location.hostname` (host yang dibuka kasir), bukan `localhost`:
>
> ```js
> const API = is5173 ? 'http://' + location.hostname + ':3000' : location.origin;
> ```
>
> Berarti dashboard yang dibuka dari PC lain di LAN langsung terhubung ke
> server (`:3000`). Tak perlu ubah kode.

> Arsitektur memakai dua port terpisah: `5173` untuk dashboard (served oleh
> Node static server di container `billing-web`), `3000` untuk API + WebSocket.
> Tidak ada reverse proxy.

---

## 4. Keamanan

### 4.1 Firewall (rekomendasi minimal)

| Port | Untuk          | Kebijakan                                    |
|------|----------------|----------------------------------------------|
| 5173 | Dashboard kasir| Wajib terbuka untuk LAN warnet               |
| 3000 | API + WebSocket client | Terbuka untuk LAN (client PC)             |
| 5432 | Postgres       | **Tertutup** (hanya internal Docker)         |
| 6379 | Redis          | **Tertutup** (hanya internal Docker)         |
| 22   | SSH            | Terbuka untuk admin saja                     |

Contoh (UWF/ufw):
```bash
sudo ufw allow 5173/tcp
sudo ufw allow 3000/tcp
sudo ufw allow 22/tcp
sudo ufw enable
```

### 4.2 Ganti password default

Belum ada endpoint ubah-password di UI. Gunakan SQL + bcrypt:

```bash
# 1) buat hash baru
docker exec billing-server node -e \
  "console.log(require('bcryptjs').hashSync(process.argv[1],10))" 'PasswordBaru123'

# 2) terapkan ke user
docker exec billing-postgres psql -U billing_user billing -c \
  "UPDATE users SET password_hash='HASH_DARI_LANGKAH_1' WHERE username='admin';"
```

Ulangi untuk user `kasir`. Jangan berbagi akun admin ke kasir.

### 4.3 Batasan yang diketahui (harus disadari sebelum go-live)

- **Tidak ada otentikasi per-endpoint.** Endpoint `/api/*` (start billing,
  tutup hari, dll.) hanya dihempas oleh CORS (`Access-Control-Allow-Origin: *`)
  dan tidak memverifikasi role admin/kasir. Siapa pun di LAN bisa `curl` API.
  → **Jangan** mengekspos sistem ke internet/Wi-Fi publik. Pastikan hanya di
  LAN tepercaya. Middleware auth disarankan sebagai pengembangan lanjutan.
- `JWT_SECRET` masih null saat ini efektif (code belum memakai JWT) — jaga
  kerahasiaan variabel `.env` tetap untuk masa depan.
- Komunikasi **tanpa TLS** (`ws://`, `http://`). Di LAN warnet ini umum dan
  dapat diterima; bila perlu, pasang reverse proxy HTTPS + `wss://`.

### 4.4 Prinsip token PC client

- Token = kredensial unik per PC (kolom `pcs.token`). **Jangan** dipakai untuk
  dua PC dan jangan diedarkan bebas.
- Jika satu PC dicuri/diganti, reset token-nya: `POST /api/pcs/:id/reset-token`
  → update `install.config` PC itu.

### 4.5 Uninstall agent memakai OTP Telegram

Agar agen tidak dibuka/di-uninstall sembarangan dari PC client, uninstaller
(silent `uninstall.ps1` maupun GUI Inno) meminta **kode OTP 6 digit** yang
server kirim ke **chat Telegram admin**:

- Setup: buat bot via **@BotFather** → `TELEGRAM_BOT_TOKEN`. Chat tujuan admin:
  `TELEGRAM_ADMIN_CHAT_ID` (nomor negatif untuk grup, lihat cara dapat ID di
  bawah). Isi keduanya di `.env` (contoh: `.env.prod.example`).
- Alur: PC jalankan uninstaller → server `POST /api/otp/request` → bot kirim
  kode ke Telegram admin → operator sebutkan ke PC / PC pegang HP admin →
  `POST /api/otp/verify` → uninstall dilanjutkan.
- Aturan kode: 6 digit, berlaku **5 menit**, sekali pakai, rate-limit **1
  request/menit per PC mesin**.
- **Fallback (mode dev):** bila `TELEGRAM_BOT_TOKEN`/`TELEGRAM_ADMIN_CHAT_ID`
  kosong, `/api/otp/request` mengembalikan `dev_code` di respon dan uninstall
  lanjut tanpa OTP. Server yang tidak terjangkau juga mengizinkan lanjut.
- Endpoint: `GET /api/otp/status`, `POST /api/otp/request`,
  `POST /api/otp/verify`. Daftar kode di tabel `otp_codes`.

Cara dapat chat ID:
```
1. Kirim pesan apa pun ke bot kamu (atau grup yang bot di-invite).
2. GET https://api.telegram.org/bot<TOKEN>/getUpdates
   → cari "chat":{"id": ...} — negatif (-100xxx) jika grup.
```

---

## 5. Database

### 5.1 Skema

Dibuat otomatis oleh `server/src/db.ts` saat server pertama kali jalan
(`CREATE TABLE IF NOT EXISTS`). Tabel: `users`, `pcs`, `vouchers`, `members`,
`billing_sessions`, `transactions`, `tutup_hari`, `audit_log`, `otp_codes`.

> Perubahan skema TIDAK otomatis meng-update tabel lama. Setelah menarik versi
> baru, cek rilis — jika ada DDL baru, jalankan ALTER/DROP secara manual
> (lihat §8).

### 5.2 Backup & Restore

Gunakan `deploy/backup.sh` (dump + gzip + simpan 14 hari):

```bash
# backup manual
chmod +x deploy/backup.sh
BACKUP_DIR=/var/backups/billing ./deploy/backup.sh

# otomatis tiap jam 03:00
sudo crontab -e
0 3 * * * BACKUP_DIR=/var/backups/billing /path/to/repo/deploy/backup.sh >> /var/log/billing-backup.log 2>&1
```

Restore:
```bash
gunzip -c billing_YYYYMMDD_HHMMSS.sql.gz | \
  docker exec -i billing-postgres psql -U billing_user billing
```

### 5.3 Reset DB (dev saja, buang data)

```bash
docker exec billing-postgres psql -U billing_user billing -c \
  "DROP TABLE IF EXISTS audit_log, tutup_hari, transactions, billing_sessions, members, vouchers, pcs, users CASCADE;"
docker compose -f docker-compose.prod.yml restart server   # ulang seed
```

---

## 6. Onboarding PC Client Windows

Alur lengkap di `client-net/installer/README-CLIENT.md`. Inti:

1. Di dashboard: tab **PC / Kartu** → **+ Tambah PC** → buat kartu (mis. `PC-01`).
2. Klik tombol **Config** di kartu → periksa **ServerUrl** (harus `ws://IP-INTERNAL:3000/socket.io/`), catat **Token**.
3. Pilih cara pasang:

   **a. Online installer (sekali klik, sarankan):** build sekali di mesin
   Windows (`build-windows.ps1`) → zip `billing-client-release.zip` otomatis
   masuk `server/agent-release/` (folder ter-volume-mount ke container).
   Di dashboard → **Config** → **Download Instal Otomatis (.bat)** → double-click
   di PC client → unduh agen dari `:3000`, pasang & online. Cek
   `http://SERVER-IP:3000/api/installer/status` → `release_ready: true`.

   **b. Manual USB:** download **install.config** → bawa + `Release` +
   `install-silent.bat` ke PC → jalankan.
4. Di dashboard, PC langsung hijau ONLINE (heartbeat ≤ 45 detik).

Saat go-live berikutnya: bersihkan 10 PC seed otomatis (`PC-01`..`PC-10`) yang
tidak dipakai, lalu buat ulang sesuai PC fisik sebenarnya.

> Jalankan `build-windows.ps1` di mesin dengan .NET 8 SDK (tidak perlu di
> server billing). Build sekali bisa dipakai semua PC — bedanya hanya isi
> `install.config` (token per PC).

---

## 7. Operasi Harian (SOP Kasir)

1. **Buka warung**: `docker compose -f docker-compose.prod.yml up -d` (atau
   pastikan 4 container `restart: unless-stopped` sudah jalan otomatis).
2. **Cek dashboard**: semua PC fisik hijau; label sewa di `Kas Hari Ini` mulai 0.
3. **Penjualan**: Start billing (nominal/jam), jual voucher, top-up member —
   semua dari dashboard. Voucher tampil sebagai kode 6 digit, 90 hari masa berlaku.
4. **Tutup hari**: sebelum tutup, katakan ke user yang masih aktif (sistem
   men-terminate semua sesi aktif). Tekan **Tutup Hari** → rekap kas per jenis
   transaksi tersimpan di `tutup_hari`.
5. **Setor kas**: cocokkan rekap Tutup Hari dengan uang fisik kasir.

Perintah server up/down/status:
```bash
docker compose -f docker-compose.prod.yml ps
docker compose -f docker-compose.prod.yml logs -f --tail=100 server
docker compose -f docker-compose.prod.yml down          # stop
docker compose -f docker-compose.prod.yml up -d          # start
```

---

## 8. Pembaruan / Update

```bash
cd /path/to/repo
git pull
docker compose -f docker-compose.prod.yml up -d --build
```

- Log: `docker compose -f docker-compose.prod.yml logs -f server web`.
- Sebelum update, lakukan backup (§5.2).
- Cek changelog untuk DDL DB; jalankan SQL manual bila ada perubahan skema.

---

## 9. Troubleshooting

| Gejala | Kemungkinan penyebab / solusi |
|--------|-------------------------------|
| PC client tidak pernah hijau | Token salah/duplikat di `install.config`; firewall memblok `:3000`; salah ServerUrl (pakai `localhost` dari PC client — harus IP server). |
| Dashboard error di LAN | §3.4 belum diterapkan (JS masih `localhost:3000`). |
| Login gagal padahal benar | Password belum diganti + hash salah ketik di UPDATE SQL; akun di-lock? (tidak ada lock — cek `audit_log`). |
| PC tampil online tapi "mati" 1 menit | Server memindai `last_seen > 45 detik`. Pastikan agen jalan (task scheduler) & tidak ada proxy yang memblok WebSocket. |
| Timer tidak berjalan | Periksa zona waktu server vs client; `docker logs billing-server` untuk error. |
| Skema error setelah update | Tabel lama belum di-ALTER/DROP (§5.1). |
| Uninstall minta OTP tapi Telegram tidak aktif | Itu **normal**: `TELEGRAM_BOT_TOKEN` kosong → server mode dev, uninstaller melanjutkan tanpa OTP. |
| OTP tidak pernah sampai ke Telegram | Cek `.env` token/chat_id, coba lagi request (rate-limit 1/menit), `docker logs billing-server` untuk error send. |
| Host `npm run build` gagal (ICU dyld) | JANGAN bangun di host — server selalu lewat Docker (`docker compose up -d --build`). |

---

## 10. Checklist Go-Live

1. [ ] `.env` dibuat dari `.env.prod.example`, password DB kuat.
2. [ ] Komposisi produksi (tanpa simulator) jalan — 4 container `Up`.
3. [ ] Dashboard dibuka via `http://SERVER-IP:5173` dari PC lain → API benar
      (§3.4), bisa login.
4. [ ] Password `admin` & `kasir` diganti (§4.2).
5. [ ] Firewall aktif: hanya 5173 (+3000 bila tidak pakai mode satu-port) + SSH.
6. [ ] 10 PC seed dibersihkan / dipetakan ke PC fisik.
7. [ ] Satu PC client uji dicoba sampai hijau ONLINE + bisa Start/Stop billing.
8. [ ] Backup terjadwal aktif + satu restore uji-coba.
9. [ ] SOP tutup hari disimulasikan sekali penuh (rekap = uang fisik).
10. [ ] Catatan batasan keamanan telah dipahami (§4.3) — sistem di LAN tepercaya.
11. [ ] (Opsional) Telegram OTP-diaktifkan: bot + chat ID terisi di `.env`
      (§4.5), uji request → kode sampai → uninstaller verifikasi.

---

## 11. Pengembangan Lanjutan yang Disarankan

- Middleware otorisasi per-role untuk semua `/api/*` (login → token JWT,
  menyingkirkan `JWT_SECRET`).
- Endpoint ubah-password + reset password dari dashboard.
- TLS/wss di depan server (ngin​x + cert) untuk LAN yang tidak tepercaya.
- Auditing terstruktur (ekspor `audit_log`/`tutup_hari` ke CSV/Excel).