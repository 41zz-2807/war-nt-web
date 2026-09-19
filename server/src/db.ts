import { Pool } from 'pg';
import bcrypt from 'bcryptjs';

export const pool = new Pool({
  connectionString:
    process.env.DATABASE_URL ||
    'postgres://billing_user:billing_pass@postgres:5432/billing',
});

const SCHEMA = `
CREATE TABLE IF NOT EXISTS users (
  id SERIAL PRIMARY KEY,
  username VARCHAR(50) UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  role VARCHAR(20) NOT NULL DEFAULT 'kasir',
  created_at TIMESTAMP DEFAULT now()
);

CREATE TABLE IF NOT EXISTS pcs (
  id SERIAL PRIMARY KEY,
  name VARCHAR(50) UNIQUE NOT NULL,
  token TEXT UNIQUE NOT NULL,
  online BOOLEAN DEFAULT false,
  last_seen TIMESTAMP,
  created_at TIMESTAMP DEFAULT now()
);

CREATE TABLE IF NOT EXISTS vouchers (
  id SERIAL PRIMARY KEY,
  code VARCHAR(6) UNIQUE NOT NULL,
  price INTEGER NOT NULL,
  minutes INTEGER NOT NULL,
  status VARCHAR(20) DEFAULT 'active',
  created_at TIMESTAMP DEFAULT now(),
  expires_at TIMESTAMP,
  used_at TIMESTAMP,
  used_by VARCHAR(50),
  revoked_at TIMESTAMP
);

CREATE TABLE IF NOT EXISTS members (
  id SERIAL PRIMARY KEY,
  name VARCHAR(50) UNIQUE NOT NULL,
  password_digit VARCHAR(4) NOT NULL,
  balance_minutes INTEGER DEFAULT 0,
  expiry_date TIMESTAMP,
  last_used TIMESTAMP,
  created_at TIMESTAMP DEFAULT now()
);

CREATE TABLE IF NOT EXISTS billing_sessions (
  id SERIAL PRIMARY KEY,
  pc_id INTEGER REFERENCES pcs(id),
  pc_name VARCHAR(50),
  started_by VARCHAR(50),
  minutes INTEGER NOT NULL,
  amount INTEGER DEFAULT 0,
  started_at TIMESTAMP DEFAULT now(),
  expires_at TIMESTAMP,
  ended_at TIMESTAMP,
  status VARCHAR(20) DEFAULT 'active',
  paid_by VARCHAR(20) DEFAULT 'cash'
);

CREATE TABLE IF NOT EXISTS transactions (
  id SERIAL PRIMARY KEY,
  type VARCHAR(30) NOT NULL,
  ref VARCHAR(50),
  amount INTEGER NOT NULL,
  minutes INTEGER DEFAULT 0,
  username VARCHAR(50),
  created_at TIMESTAMP DEFAULT now()
);

CREATE TABLE IF NOT EXISTS tutup_hari (
  id SERIAL PRIMARY KEY,
  closed_at TIMESTAMP DEFAULT now(),
  total_kas INTEGER DEFAULT 0,
  total_transaksi INTEGER DEFAULT 0,
  detail JSONB
);

CREATE TABLE IF NOT EXISTS audit_log (
  id SERIAL PRIMARY KEY,
  username VARCHAR(50),
  action VARCHAR(100),
  details TEXT,
  created_at TIMESTAMP DEFAULT now()
);
`;

export function randomToken(): string {
  let t = '';
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  for (let i = 0; i < 24; i++) t += chars[Math.floor(Math.random() * chars.length)];
  return t;
}

export function randomVoucherCode(): string {
  return String(Math.floor(100000 + Math.random() * 900000));
}

export function toMinutes(amount: number): number {
  const rateMenit = 20; // Rp 1000 = 20 menit
  return Math.round((amount / 1000) * rateMenit);
}

export async function initSchema(): Promise<void> {
  await pool.query(SCHEMA);

  const users = await pool.query('SELECT COUNT(*)::int AS c FROM users');
  if (users.rows[0].c === 0) {
    const adminHash = await bcrypt.hash('admin123', 10);
    const kasirHash = await bcrypt.hash('admin123', 10);
    await pool.query(
      'INSERT INTO users (username, password_hash, role) VALUES ($1,$2,$3), ($4,$5,$6)',
      ['admin', adminHash, 'admin', 'kasir', kasirHash, 'kasir']
    );
    console.log('[init] users seeded (admin/kasir, password: admin123)');
  }

  const pcs = await pool.query('SELECT COUNT(*)::int AS c FROM pcs');
  if (pcs.rows[0].c === 0) {
    for (let i = 1; i <= 10; i++) {
      const name = 'PC-' + String(i).padStart(2, '0');
      await pool.query('INSERT INTO pcs (name, token) VALUES ($1, $2)', [name, randomToken()]);
    }
    console.log('[init] 10 PC slots seeded');
  }
}