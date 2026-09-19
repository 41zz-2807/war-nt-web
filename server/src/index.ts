import express from 'express';
import http from 'http';
import path from 'path';
import fs from 'fs';
import { Server as SocketIOServer } from 'socket.io';
import bcrypt from 'bcryptjs';
import { pool, initSchema, randomToken, randomVoucherCode, toMinutes } from './db';
import { sendTelegram, telegramEnabled, telegramChatLabel } from './telegram';

const app = express();
app.use(express.json());

// Folder agen client Windows siap-unduh (dari build-windows.ps1).
const AGENT_DIR = path.join(__dirname, '..', 'agent-release');
app.use('/agent', express.static(AGENT_DIR));
app.get('/api/installer/status', (req, res) => {
  let release_ready = false;
  let size = 0;
  try {
    const p = path.join(AGENT_DIR, 'billing-client-release.zip');
    if (fs.existsSync(p)) {
      release_ready = true;
      size = fs.statSync(p).size;
    }
  } catch (e) {
    // abaikan
  }
  res.json({
    release_ready,
    size,
    agent_url: '/agent/billing-client-release.zip',
    note: release_ready
      ? null
      : 'Belum ada release. Bangun di mesin Windows (build-windows.ps1), lalu salin billing-client-release.zip ke server/agent-release/.',
  });
});

app.use((req, res, next) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') return res.sendStatus(204);
  next();
});

const server = http.createServer(app);
const io = new SocketIOServer(server, {
  cors: { origin: '*', methods: ['GET', 'POST'] },
});

const PORT = 3000;

/* ---------- helpers ---------- */

function validAmount(a: number): boolean {
  return Number.isInteger(a) && a >= 1000 && a % 500 === 0;
}

async function audit(username: string, action: string, details: string) {
  try {
    await pool.query('INSERT INTO audit_log (username, action, details) VALUES ($1,$2,$3)', [
      username || 'system',
      action,
      details,
    ]);
  } catch (e) {
    console.error('audit err', e);
  }
}

async function expireStaleSessions() {
  await pool.query(
    "UPDATE billing_sessions SET status='expired', ended_at=now() WHERE status='active' AND expires_at <= now()"
  );
}

async function expireVouchers() {
  await pool.query(
    "UPDATE vouchers SET status='expired' WHERE status='active' AND expires_at < now()"
  );
}

async function markOnline(pcId: number) {
  await pool.query('UPDATE pcs SET online=true, last_seen=now() WHERE id=$1', [pcId]);
}

async function markOffline(pcId: number) {
  await pool.query('UPDATE pcs SET online=false WHERE id=$1', [pcId]);
}

/* ---------- auth ---------- */

app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

app.post('/api/auth/login', async (req, res) => {
  try {
    const { username, password } = req.body;
    const r = await pool.query('SELECT * FROM users WHERE username=$1', [username || '']);
    const user = r.rows[0];
    if (!user) return res.status(401).json({ message: 'User tidak ditemukan' });
    const ok = await bcrypt.compare(String(password || ''), user.password_hash);
    if (!ok) return res.status(401).json({ message: 'Password salah' });
    await audit(user.username, 'login', 'login sukses');
    res.json({ message: 'Login successful', user: user.username, role: user.role });
  } catch (e) {
    console.error(e);
    res.status(500).json({ message: 'Server error' });
  }
});

app.post('/api/auth/logout', async (req, res) => {
  try {
    const { username } = req.body;
    await audit(username, 'logout', 'logout');
    res.json({ message: 'Logged out' });
  } catch (e) {
    res.status(500).json({ message: 'Server error' });
  }
});

/* ---------- dashboard ---------- */

app.get('/api/admin/dashboard', async (req, res) => {
  try {
    await expireStaleSessions();
    const active = await pool.query(
      "SELECT COUNT(*)::int AS c FROM billing_sessions WHERE status='active'"
    );
    const totalToday = await pool.query(
      'SELECT COUNT(*)::int AS c FROM billing_sessions WHERE started_at::date = CURRENT_DATE'
    );
    const kasToday = await pool.query(
      'SELECT COALESCE(SUM(amount),0)::int AS c FROM transactions WHERE created_at::date = CURRENT_DATE'
    );
    const pcs = await pool.query('SELECT id, name, online, last_seen FROM pcs ORDER BY id');
    res.json({
      message: 'Admin dashboard',
      active_sessions: active.rows[0].c,
      total_sessions: totalToday.rows[0].c,
      total_kas: kasToday.rows[0].c,
      pc_list: pcs.rows,
    });
  } catch (e) {
    console.error(e);
    res.status(500).json({ message: 'Server error' });
  }
});

app.get('/api/kasir/dashboard', async (req, res) => {
  try {
    await expireStaleSessions();
    const active = await pool.query(
      "SELECT COUNT(*)::int AS c FROM billing_sessions WHERE status='active'"
    );
    const totalToday = await pool.query(
      'SELECT COUNT(*)::int AS c FROM billing_sessions WHERE started_at::date = CURRENT_DATE'
    );
    const pcs = await pool.query('SELECT id, name, online, last_seen FROM pcs ORDER BY id');
    res.json({
      message: 'Kasir dashboard',
      active_sessions: active.rows[0].c,
      total_sessions: totalToday.rows[0].c,
      pc_list: pcs.rows,
    });
  } catch (e) {
    console.error(e);
    res.status(500).json({ message: 'Server error' });
  }
});

/* ---------- PC CRUD ---------- */

app.get('/api/pcs', async (req, res) => {
  try {
    const r = await pool.query('SELECT id, name, online, last_seen, token FROM pcs ORDER BY id');
    res.json({ pc_list: r.rows });
  } catch (e) {
    res.status(500).json({ message: 'Server error' });
  }
});

app.post('/api/pcs', async (req, res) => {
  try {
    const name = String(req.body.name || '').trim().toUpperCase();
    if (!name) return res.status(400).json({ message: 'Nama PC wajib diisi' });
    const exists = await pool.query('SELECT id FROM pcs WHERE name=$1', [name]);
    if (exists.rows.length) return res.status(400).json({ message: 'Nama PC sudah ada' });
    const r = await pool.query('INSERT INTO pcs (name, token) VALUES ($1,$2) RETURNING *', [
      name,
      randomToken(),
    ]);
    await audit(req.body.username, 'pc:add', 'tambah PC ' + name);
    io.emit('pcs:sync');
    res.json({ message: 'PC ditambahkan', pc: r.rows[0] });
  } catch (e) {
    res.status(500).json({ message: 'Server error' });
  }
});

app.delete('/api/pcs/:id', async (req, res) => {
  try {
    const id = Number(req.params.id);
    const pc = await pool.query('SELECT * FROM pcs WHERE id=$1', [id]);
    if (!pc.rows.length) return res.status(404).json({ message: 'PC tidak ditemukan' });
    await pool.query('DELETE FROM pcs WHERE id=$1', [id]);
    await audit(req.body.username, 'pc:delete', 'hapus PC ' + pc.rows[0].name);
    io.emit('pcs:sync');
    res.json({ message: 'PC dihapus' });
  } catch (e) {
    res.status(500).json({ message: 'Server error' });
  }
});

app.post('/api/pcs/:id/reset-token', async (req, res) => {
  try {
    const id = Number(req.params.id);
    const token = randomToken();
    await pool.query('UPDATE pcs SET token=$1 WHERE id=$2', [token, id]);
    res.json({ message: 'Token PC direset', token });
  } catch (e) {
    res.status(500).json({ message: 'Server error' });
  }
});

/* ---------- billing ---------- */

app.get('/api/billing/sessions', async (req, res) => {
  try {
    await expireStaleSessions();
    const r = await pool.query(
      "SELECT * FROM billing_sessions WHERE status=$1 OR $1=''::text ORDER BY started_at DESC",
      [req.query.status || '']
    );
    res.json({ sessions: r.rows });
  } catch (e) {
    res.status(500).json({ message: 'Server error' });
  }
});

app.post('/api/billing/start', async (req, res) => {
  try {
    const { pc_id, hours, minutes, amount, member_id, username } = req.body;
    const pc = await pool.query('SELECT * FROM pcs WHERE id=$1', [Number(pc_id)]);
    if (!pc.rows.length) return res.status(404).json({ message: 'PC tidak ditemukan' });
    if (!pc.rows[0].online)
      return res.status(409).json({ message: 'PC sedang OFFLINE — nyalakan agen client dulu sebelum start billing' });

    let finalMinutes = 0;
    let finalAmount = 0;
    let paidBy = 'cash';
    let memberRows: any[] = [];

    if (member_id) {
      const mr = await pool.query('SELECT * FROM members WHERE id=$1', [Number(member_id)]);
      if (!mr.rows.length) return res.status(404).json({ message: 'Member tidak ditemukan' });
      if ((mr.rows[0].balance_minutes || 0) <= 0)
        return res.status(400).json({ message: 'Saldo member kosong' });
      if (minutes) finalMinutes = Math.round(Number(minutes));
      else if (hours) finalMinutes = Math.round(Number(hours) * 60);
      else return res.status(400).json({ message: 'Tentukan durasi (menit/jam) untuk member' });
      if (finalMinutes > mr.rows[0].balance_minutes)
        return res.status(400).json({ message: 'Saldo member tidak cukup' });
      paidBy = 'member';
      finalAmount = 0;
      memberRows = mr.rows;
      await pool.query('UPDATE members SET balance_minutes = balance_minutes - $1, last_used=now() WHERE id=$2', [
        finalMinutes,
        Number(member_id),
      ]);
    } else if (amount) {
      if (!validAmount(Number(amount)))
        return res.status(400).json({ message: 'Nominal minimal Rp 1.000 dan kelipatan Rp 500' });
      finalAmount = Number(amount);
      finalMinutes = toMinutes(finalAmount);
    } else if (minutes) {
      finalMinutes = Math.round(Number(minutes));
      finalAmount = toMinutes(finalMinutes) ? Math.round((finalMinutes / 20) * 1000) : 0;
    } else if (hours) {
      finalMinutes = Math.round(Number(hours) * 60);
      finalAmount = Math.round(Number(hours) * 3000);
    } else {
      return res.status(400).json({ message: 'Tentukan nominal / jam / menit' });
    }

    if (finalMinutes <= 0 || finalMinutes > 1440)
      return res.status(400).json({ message: 'Durasi tidak valid' });

    const pcName = pc.rows[0].name;
    const expiresAt = new Date(Date.now() + finalMinutes * 60000);
    const r = await pool.query(
      `INSERT INTO billing_sessions (pc_id, pc_name, started_by, minutes, amount, expires_at, paid_by)
       VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING *`,
      [pc.rows[0].id, pcName, username || 'kasir', finalMinutes, finalAmount, expiresAt, paidBy]
    );

    if (memberRows.length) {
      await pool.query('INSERT INTO transactions (type, ref, amount, minutes, username) VALUES ($1,$2,$3,$4,$5)', [
        'member_usage',
        'member-' + member_id,
        0,
        finalMinutes,
        username || 'kasir',
      ]);
    } else {
      await pool.query('INSERT INTO transactions (type, ref, amount, minutes, username) VALUES ($1,$2,$3,$4,$5)', [
        'billing',
        'sesi-' + r.rows[0].id,
        finalAmount,
        finalMinutes,
        username || 'kasir',
      ]);
    }

    await audit(username, 'billing:start', 'start sesi ' + pcName + ' ' + finalMinutes + ' menit');
    io.emit('session:started', { pc_id: pc.rows[0].id, pc_name: pcName, minutes: finalMinutes });
    res.json({ message: 'Sesi dimulai', session: r.rows[0] });
  } catch (e) {
    console.error(e);
    res.status(500).json({ message: 'Server error' });
  }
});

app.post('/api/billing/stop', async (req, res) => {
  try {
    const { session_id, pc_id, username } = req.body;
    let sess;
    if (session_id) {
      const r = await pool.query(
        "UPDATE billing_sessions SET status='settled', ended_at=now() WHERE id=$1 AND status='active' RETURNING *",
        [Number(session_id)]
      );
      sess = r.rows[0];
    } else if (pc_id) {
      const r = await pool.query(
        "UPDATE billing_sessions SET status='settled', ended_at=now() WHERE pc_id=$1 AND status='active' RETURNING *",
        [Number(pc_id)]
      );
      sess = r.rows[0];
    }
    if (!sess) return res.status(404).json({ message: 'Sesi aktif tidak ditemukan' });
    await audit(username, 'billing:stop', 'stop sesi #' + sess.id);
    io.emit('session:stopped', { session_id: sess.id, pc_id: sess.pc_id });
    res.json({ message: 'Sesi dihentikan', session: sess });
  } catch (e) {
    res.status(500).json({ message: 'Server error' });
  }
});

/* ---------- voucher ---------- */

app.post('/api/voucher/jual', async (req, res) => {
  try {
    const price = Number(req.body.price);
    if (!validAmount(price))
      return res.status(400).json({ message: 'Harga minimal Rp 1.000 dan kelipatan Rp 500' });
    const minutes = toMinutes(price);
    let code = randomVoucherCode();
    let dup = true;
    while (dup) {
      const ck = await pool.query('SELECT id FROM vouchers WHERE code=$1', [code]);
      if (!ck.rows.length) dup = false;
      else code = randomVoucherCode();
    }
    const expiresAt = new Date(Date.now() + 90 * 24 * 3600 * 1000);
    const r = await pool.query(
      `INSERT INTO vouchers (code, price, minutes, status, expires_at)
       VALUES ($1,$2,$3,'active',$4) RETURNING *`,
      [code, price, minutes, expiresAt]
    );
    await pool.query('INSERT INTO transactions (type, ref, amount, minutes, username) VALUES ($1,$2,$3,$4,$5)', [
      'voucher',
      'voucher-' + code,
      price,
      minutes,
      req.body.username || 'kasir',
    ]);
    await audit(req.body.username, 'voucher:sell', 'jual voucher ' + code + ' Rp' + price);
    res.json({ message: 'Voucher terjual', voucher: r.rows[0] });
  } catch (e) {
    console.error(e);
    res.status(500).json({ message: 'Server error' });
  }
});

app.get('/api/voucher/history', async (req, res) => {
  try {
    await expireVouchers();
    const r = await pool.query('SELECT * FROM vouchers ORDER BY created_at DESC');
    res.json({ vouchers: r.rows });
  } catch (e) {
    res.status(500).json({ message: 'Server error' });
  }
});

app.post('/api/voucher/revoke/:id', async (req, res) => {
  try {
    const id = Number(req.params.id);
    const r = await pool.query(
      "UPDATE vouchers SET status='revoked', revoked_at=now() WHERE id=$1 AND status='active' RETURNING *",
      [id]
    );
    if (!r.rows.length) return res.status(404).json({ message: 'Voucher tidak ditemukan / sudah tidak aktif' });
    await audit(req.body.username, 'voucher:revoke', 'revoke voucher ' + r.rows[0].code);
    res.json({ message: 'Voucher direvoke', voucher: r.rows[0] });
  } catch (e) {
    res.status(500).json({ message: 'Server error' });
  }
});

/* ---------- member ---------- */

app.post('/api/member/create', async (req, res) => {
  try {
    const name = String(req.body.name || '').trim();
    const pwd = String(req.body.password || '');
    if (!name) return res.status(400).json({ message: 'Nama member wajib diisi' });
    if (!/^\d{4}$/.test(pwd))
      return res.status(400).json({ message: 'Password harus 4 digit angka' });
    const exists = await pool.query('SELECT id FROM members WHERE name=$1', [name]);
    if (exists.rows.length) return res.status(400).json({ message: 'Nama member sudah ada' });
    const expiry = new Date(Date.now() + 90 * 24 * 3600 * 1000);
    const r = await pool.query(
      'INSERT INTO members (name, password_digit, expiry_date) VALUES ($1,$2,$3) RETURNING *',
      [name, pwd, expiry]
    );
    await audit(req.body.username, 'member:create', 'buat member ' + name);
    res.json({ message: 'Member dibuat', member: r.rows[0] });
  } catch (e) {
    res.status(500).json({ message: 'Server error' });
  }
});

app.get('/api/member/list', async (req, res) => {
  try {
    const r = await pool.query(
      "SELECT id, name, password_digit, balance_minutes, expiry_date, last_used, created_at FROM members ORDER BY created_at DESC"
    );
    res.json({ members: r.rows });
  } catch (e) {
    res.status(500).json({ message: 'Server error' });
  }
});

app.post('/api/member/topup', async (req, res) => {
  try {
    const { member_id, name, amount } = req.body;
    if (!validAmount(Number(amount)))
      return res.status(400).json({ message: 'Top-up minimal Rp 1.000 dan kelipatan Rp 500' });
    let member;
    if (member_id) {
      const r = await pool.query('SELECT * FROM members WHERE id=$1', [Number(member_id)]);
      member = r.rows[0];
    } else if (name) {
      const r = await pool.query('SELECT * FROM members WHERE name=$1', [String(name).trim()]);
      member = r.rows[0];
    }
    if (!member) return res.status(404).json({ message: 'Member tidak ditemukan' });
    const minutes = toMinutes(Number(amount));
    await pool.query('UPDATE members SET balance_minutes = balance_minutes + $1 WHERE id=$2', [
      minutes,
      member.id,
    ]);
    await pool.query('INSERT INTO transactions (type, ref, amount, minutes, username) VALUES ($1,$2,$3,$4,$5)', [
      'member_topup',
      'member-' + member.id,
      Number(amount),
      minutes,
      req.body.username || 'kasir',
    ]);
    await audit(req.body.username, 'member:topup', 'topup ' + member.name + ' Rp' + amount);
    res.json({ message: 'Top-up berhasil', member_id: member.id, minutes_added: minutes });
  } catch (e) {
    res.status(500).json({ message: 'Server error' });
  }
});

app.post('/api/member/login', async (req, res) => {
  try {
    const { name, password } = req.body;
    const r = await pool.query('SELECT * FROM members WHERE name=$1', [String(name || '').trim()]);
    const m = r.rows[0];
    if (!m) return res.status(404).json({ message: 'Member tidak ditemukan' });
    if (m.password_digit !== String(password || ''))
      return res.status(401).json({ message: 'Password salah' });
    const expired = m.expiry_date && new Date(m.expiry_date) < new Date();
    res.json({
      message: 'Login member berhasil',
      member: { id: m.id, name: m.name, balance_minutes: m.balance_minutes, expired: !!expired },
    });
  } catch (e) {
    res.status(500).json({ message: 'Server error' });
  }
});

/* ---------- tutup hari ---------- */

app.post('/api/tutup-hari', async (req, res) => {
  try {
    await expireStaleSessions();
    const kas = await pool.query(
      'SELECT COALESCE(SUM(amount),0)::int AS total, COUNT(*)::int AS cnt FROM transactions WHERE created_at::date = CURRENT_DATE'
    );
    const byType = await pool.query(
      'SELECT type, COALESCE(SUM(amount),0)::int AS jml, COUNT(*)::int AS n FROM transactions WHERE created_at::date = CURRENT_DATE GROUP BY type'
    );
    const detail = { by_type: byType.rows };
    const r = await pool.query(
      'INSERT INTO tutup_hari (total_kas, total_transaksi, detail) VALUES ($1,$2,$3) RETURNING *',
      [kas.rows[0].total, kas.rows[0].cnt, JSON.stringify(detail)]
    );
    await pool.query("UPDATE billing_sessions SET status='settled', ended_at=now() WHERE status='active'");
    res.json({ message: 'Hari ditutup', tutup: r.rows[0] });
  } catch (e) {
    res.status(500).json({ message: 'Server error' });
  }
});

app.get('/api/tutup-hari/last', async (req, res) => {
  try {
    const r = await pool.query('SELECT * FROM tutup_hari ORDER BY closed_at DESC LIMIT 1');
    res.json({ tutup: r.rows[0] || null });
  } catch (e) {
    res.status(500).json({ message: 'Server error' });
  }
});

app.get('/api/audit', async (req, res) => {
  try {
    const r = await pool.query('SELECT * FROM audit_log ORDER BY created_at DESC LIMIT 100');
    res.json({ logs: r.rows });
  } catch (e) {
    res.status(500).json({ message: 'Server error' });
  }
});

/* ---------- OTP (uninstall agent via Telegram) ---------- */

const otpRate = new Map<string, number>();

const OTP_TTL_MS = 5 * 60 * 1000; // 5 menit
const OTP_MIN_INTERVAL_MS = 60 * 1000; // minimal 1 menit antar request per PC

function randomOtp(): string {
  return String(Math.floor(100000 + Math.random() * 900000));
}

app.get('/api/otp/status', (req, res) => {
  const en = telegramEnabled();
  res.json({
    enabled: en,
    chat_id: en ? telegramChatLabel() : null,
  });
});

app.post('/api/otp/request', async (req, res) => {
  try {
    const pc_name = String(req.body.pc_name || '').trim().toUpperCase();
    const purpose = String(req.body.purpose || 'uninstall');
    if (!pc_name) return res.status(400).json({ message: 'Nama PC wajib diisi' });

    const last = otpRate.get(pc_name) || 0;
    if (Date.now() - last < OTP_MIN_INTERVAL_MS)
      return res.status(429).json({ message: 'Tunggu 1 menit sebelum request OTP lagi' });
    otpRate.set(pc_name, Date.now());

    const code = randomOtp();
    const expires = new Date(Date.now() + OTP_TTL_MS);
    await pool.query(
      'INSERT INTO otp_codes (code, purpose, ref, expires_at) VALUES ($1,$2,$3,$4)',
      [code, purpose, pc_name, expires]
    );

    const text = `🔐 OTP ${purpose} · PC ${pc_name}\nKode: ${code}\nBerlaku 5 menit. Jangan bocorkan.`;
    const sent = await sendTelegram(text);

    if (telegramEnabled()) {
      await audit(req.body.username, 'otp:request', 'request OTP ' + purpose + ' PC ' + pc_name);
      return res.json({ ok: true, message: 'OTP dikirim ke Telegram admin', ttl: OTP_TTL_MS / 1000, sent: sent.ok });
    }
    // Telegram belum dikonfigurasi -> mode dev: kode dikembalikan di respon.
    return res.json({
      ok: true,
      dev_code: code,
      message: 'Telegram belum dikonfigurasi — mode dev, kode tampil di sini',
    });
  } catch (e) {
    console.error(e);
    res.status(500).json({ message: 'Server error' });
  }
});

app.post('/api/otp/verify', async (req, res) => {
  try {
    const pc_name = String(req.body.pc_name || '').trim().toUpperCase();
    const purpose = String(req.body.purpose || 'uninstall');
    const code = String(req.body.code || '').trim();

    const r = await pool.query(
      'SELECT * FROM otp_codes WHERE ref=$1 AND purpose=$2 AND used=false AND expires_at > now() ORDER BY created_at DESC LIMIT 1',
      [pc_name, purpose]
    );
    const otp = r.rows[0];
    if (!otp) return res.status(400).json({ ok: false, message: 'OTP tidak ditemukan / sudah kadaluarsa' });
    if (otp.code !== code) return res.status(400).json({ ok: false, message: 'Kode OTP salah' });

    await pool.query('UPDATE otp_codes SET used=true WHERE id=$1', [otp.id]);
    await audit(req.body.username, 'otp:verify', 'verifikasi OTP ' + purpose + ' PC ' + pc_name);
    res.json({ ok: true, message: 'OTP valid — silakan lanjutkan' });
  } catch (e) {
    console.error(e);
    res.status(500).json({ message: 'Server error' });
  }
});

// Bersihkan OTP lama (expired/terpakai) — 1x per 6 jam
setInterval(() => {
  pool
    .query("DELETE FROM otp_codes WHERE (used=true OR expires_at < now()) AND created_at < now() - interval '1 day'")
    .catch(() => {});
}, 6 * 3600 * 1000);

/* ---------- web socket (client token auth) ---------- */

io.use((socket, next) => {
  const auth: any = socket.handshake.auth || {};
  if (auth.web) return next();
  if (!auth.token) return next(new Error('missing token'));
  pool
    .query('SELECT id, name FROM pcs WHERE token=$1', [auth.token])
    .then((r: { rows: { id: number; name: string }[] }) => {
      if (!r.rows.length) return next(new Error('token tidak dikenal'));
      socket.data.pcId = r.rows[0].id;
      socket.data.pcName = r.rows[0].name;
      next();
    })
    .catch(() => next(new Error('db error')));
});

io.on('connection', (socket) => {
  if (socket.data.pcId) {
    const pcId: number = socket.data.pcId;
    const pcName: string = socket.data.pcName;
    markOnline(pcId).catch(() => {});
    socket.join('pc:' + pcId);
    socket.emit('pc:status', { connected: true, pcId, pcName });
    io.emit('pcs:sync');
    socket.on('heartbeat', () => {
      pool.query('UPDATE pcs SET last_seen=now() WHERE id=$1', [pcId]).catch(() => {});
    });
    socket.on('disconnect', () => {
      markOffline(pcId).catch(() => {});
      io.emit('pcs:sync');
    });
  }
});

setInterval(() => {
  pool
    .query("UPDATE pcs SET online=false WHERE last_seen < now() - interval '45 seconds'")
    .catch(() => {});
}, 20000);

/* ---------- init & start ---------- */

initSchema()
  .then(() => {
    server.listen(PORT, () => {
      console.log(`Server running on port ${PORT}`);
    });
  })
  .catch((e) => {
    console.error('init schema failed', e);
    process.exit(1);
  });

export { app, server, io };