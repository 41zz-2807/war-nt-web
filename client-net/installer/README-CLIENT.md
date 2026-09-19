# Instalasi Agen Client Warnet (Windows)

Agen ini yang dipasang di tiap PC warnet. Fungsinya:

- **Konek otomatis** ke server billing via WebSocket + token PC (validasi server).
- **Auto-start saat user login** (Scheduled Task) tanpa jendela konsol.
- **Hardening per user**: kunci Task Manager, RegEdit, CMD, Run, Control Panel
  (diterapkan tiap login, dipulihkan saat uninstall).
- Menerima event server: `timer:update`, `session:started`, `session:stopped`
  untuk tampilan sisa waktu / lock screen di PC client.

---

## 1. Siapkan dulu (di server / kasir)

1. Buka dashboard `http://<IP-SERVER>:5173` → login `admin`/`admin123` atau `kasir`/`admin123`.
2. Buka tab **PC Simulasi** → pastikan PC yang mau dipasangi agen sudah ada
   (buat kartu PC baru jika belum). Token tiap PC tampil di kartu/bagian detail PC.
   Token satu PC **berbeda** dengan PC lain dan tidak boleh dipakai 2 PC.

> Catatan: cara mudah dapatkan semua token: `curl http://<IP-SERVER>:3000/api/pcs`

## 2. Build agen (di PC mana pun yang ada dotnet 8 SDK)

Karena repo dikembangkan di Docker (host Node.js sudah lolos), agen Windows
di-build terpisah. Di folder `client-net/installer`:

```powershell
powershell -ExecutionPolicy Bypass -File build-windows.ps1
```

Hasil `client-net.exe` + `client-net.dll.config` masuk ke `installer\Release\`.

## 3. Konfigurasi

Salin `install.config.example` → `install.config`, lalu isi:

```
ServerUrl=ws:// IP-ADDRESS-SERVER :3000/socket.io/
Token=<TOKEN_PC_TIAP_PC_BERBEDA>
PCName=PC-01
```

- `ServerUrl`: pakai **IP LAN server warnet** (bukan `localhost`, PC client beda mesin).
- `Token`: token unik PC ini (dari langkah 1).

## 4. Instal — pilih salah satu

### Opsi A — Silent (tanpa tool tambahan, disarankan untuk banyak PC)
1. Letakkan `install.config` + `install-silent.bat` + `install-silent.ps1`
   + `run-hidden.vbs` + isi folder `Release` di PC target (mis. via flashdisk/`net use`).
2. Klik dua kali **install-silent.bat** → setujui UAC.
3. Selesai. Agen langsung jalan tersembunyi + otomatis tiap login.

### Opsi B — GUI installer (Inno Setup)
Prasyarat: Inno Setup 6 terpasang. `client-net/installer`:

```
ISCC.exe WarnetClientSetup.iss      # menghasilkan dist\WarnetClientSetup.exe
```

Bawa `WarnetClientSetup.exe` ke PC target, jalankan, isi Server URL + Token
di wizard. Hadir dengan uninstaller bawaan Windows.

Bisa juga silent dari jarak jauh:

```
WarnetClientSetup.exe /VERYSILENT /ServerUrl="ws://192.168.1.10:3000/socket.io/" /Token="abc123" /PCName="PC-01"
```

## 5. Verifikasi

- Di dashboard kasir: PC muncul **ONLINE (hijau)** saat agen jalan.
- Di PC client: Task Manager / RegEdit / CMD terkunci (peringatan kebijakan).
- Cek pakai `schtasks /query /tn WarnetBillingClient` (status Ready).
- Jalankan manual: `"C:\Program Files\WarnetBillingClient\client-net.exe"`.

## 6. Ubah konfigurasi setelah instal

Edit `C:\Program Files\WarnetBillingClient\client-net.dll.config`
(ServerUrl / Token / PcId), lalu restart agen (atau log off-log on).

## 7. Uninstall

- Silent: klik **uninstall.bat** (setujui UAC) → task dihapus, hardening
  dipulihkan, folder dihapus.
- Inno: Control Panel → Programs → `Warnet Billing Client Agent` → Uninstall.

---

## Catatan teknis

- `.NET 8` runtime dibutuhkan di PC client (atau build dengan `--self-contained`).
- `Program.cs` mengirim Socket.IO `CONNECT 40{"auth":{"token":"..."}}` —
  server hanya menerima token yang valid (kolom `pcs.token`).
- `run-hidden.vbs` dipanggil Scheduled Task `WarnetBillingClient` (trigger ONLOGON)
  dan menulis ulang registry hardening per user sebelum menjalankan agen.
- Log aktivitas agen hanya di console (tersembunyi); untuk debugging
  sementara, jalankan `client-net.exe` langsung via CMD.