/*
 * PC Client Simulator — mensimulasikan banyak PC client warnet.
 *
 * Cara kerja:
 *  - Polling /api/pcs ke billing-server setiap 5 detik.
 *  - Untuk setiap PC yang belum terhubung (sampai batas SIM_MAX),
 *    konek lewat WebSocket/Socket.IO memakai token PC.
 *  - "heartbeat" tiap 10 detik biar status PC tetap online (hijau).
 *  - Jika PC dihapus/ditambah di dashboard, simulator ikut menyesuaikan.
 *
 * Env:
 *  SERVER_URL = http://server:3000  (alamat billing-server)
 *  SIM_MAX    = 30                  (jumlah maksimum PC yang disimulasikan)
 */
const baseUrl = process.env.SERVER_URL || 'http://server:3000';
const maxClients = parseInt(process.env.SIM_MAX || '30', 10);

const { io } = require('socket.io-client');

const clients = new Map(); // pcId -> { socket, heartbeat }

async function fetchJson(path, opts) {
  const res = await fetch(baseUrl + path, opts || {});
  if (!res.ok) {
    const msg = await res.json().catch(() => ({}));
    throw new Error(msg.message || ('HTTP ' + res.status));
  }
  return res.json();
}

function connectPC(pc) {
  const socket = io(baseUrl, {
    auth: { token: pc.token },
    transports: ['websocket'],
    reconnection: true,
  });

  const hb = setInterval(() => {
    if (socket.connected) socket.emit('heartbeat');
  }, 10000);

  const entry = { socket, hb };
  clients.set(pc.id, entry);

  socket.on('connect', () => {
    console.log('[sim] PC#' + pc.id + ' ' + pc.name + ' TERHUBUNG (online)');
  });

  socket.on('pc:status', (d) => {
    console.log('[sim] ' + pc.name + ' pc:status ->', JSON.stringify(d));
  });

  socket.on('session:started', (d) => {
    console.log('[sim] ' + pc.name + ' sesi dimulai ' + (d.minutes || '?') + ' menit');
  });

  socket.on('session:stopped', (d) => {
    console.log('[sim] ' + pc.name + ' sesi dihentikan');
  });

  socket.on('timer:update', (d) => {
    console.log('[sim] ' + pc.name + ' timer ->', JSON.stringify(d));
  });

  socket.on('connect_error', (err) => {
    console.error('[sim] PC#' + pc.id + ' ' + pc.name + ' connect_error:', err.message);
  });

  socket.on('disconnect', () => {
    clearInterval(hb);
    if (clients.get(pc.id) === entry) clients.delete(pc.id);
    console.log('[sim] ' + pc.name + ' TERPUTUS');
  });
}

async function syncPCs() {
  try {
    const data = await fetchJson('/api/pcs');
    const pcs = data.pc_list || [];

    for (const pc of pcs) {
      if (clients.size >= maxClients) break;
      if (!clients.has(pc.id) && pc.token) connectPC(pc);
    }

    const valid = new Set(pcs.map((p) => p.id));
    for (const id of [...clients.keys()]) {
      if (!valid.has(id)) {
        try {
          clients.get(id).socket.close();
        } catch (e) {}
      }
    }
  } catch (e) {
    console.error('[sim] sync error:', e.message);
  }
}

console.log('[sim] PC Client Simulator aktif, max =', maxClients, ', server =', baseUrl);
syncPCs();
setInterval(syncPCs, 5000);

process.on('SIGINT', () => {
  console.log('[sim] mematikan semua client...');
  for (const e of clients.values()) {
    try {
      e.socket.close();
    } catch (err) {}
  }
  process.exit(0);
});