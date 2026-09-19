/*
 * Client Simulator - mensimulasikan PC client Windows (.NET agent)
 * Dipakai untuk testing koneksi WebSocket dengan token ke billing-server.
 *
 * Usage:
 *   node tools/client-simulator.js <TOKEN_PC> [serverUrl]
 *
 * Contoh:
 *   docker exec billing-server node tools/client-simulator.js ABC123...xyz
 */
const token = process.argv[2];
const serverUrl = process.argv[3] || 'http://localhost:3000';

if (!token) {
  console.error('Gunakan: node tools/client-simulator.js <TOKEN_PC>');
  process.exit(1);
}

const { io } = require('socket.io-client');

console.log('[simulator] Menghubungkan dengan token:', token.slice(0, 6) + '...');
const socket = io(serverUrl, {
  auth: { token },
  transports: ['websocket'],
});

let lastPing = 0;

socket.on('connect', () => {
  console.log('[simulator] TERHUBUNG - PC dianggap online (hijau di dashboard)');
  lastPing = Date.now();
});

socket.on('pc:status', (d) => {
  console.log('[simulator] pc:status ->', JSON.stringify(d));
});

socket.on('session:started', (d) => {
  console.log('[simulator] session:started ->', JSON.stringify(d));
});

socket.on('session:stopped', (d) => {
  console.log('[simulator] session:stopped ->', JSON.stringify(d));
});

socket.on('timer:update', (d) => {
  console.log('[simulator] timer:update ->', JSON.stringify(d));
});

socket.on('disconnect', () => {
  console.log('[simulator] TERPUTUS');
});

socket.on('connect_error', (err) => {
  console.error('[simulator] error koneksi:', err.message);
  process.exit(1);
});

// heartbeat tiap 10 detik biar tetap online
setInterval(() => {
  if (socket.connected) {
    socket.emit('heartbeat');
    lastPing = Date.now();
  }
}, 10000);

process.on('SIGINT', () => {
  console.log('\n[simulator] keluar');
  socket.close();
  process.exit(0);
});