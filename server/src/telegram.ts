// ============================================================================
//  telegram.ts - integrasi Telegram Bot (kirim pesan OTP ke admin).
//  Konfigurasi via env:
//    TELEGRAM_BOT_TOKEN   - token bot dari @BotFather
//    TELEGRAM_ADMIN_CHAT_ID - chat ID admin/group (mis. tempat operator warnet)
// ============================================================================

const TOKEN = process.env.TELEGRAM_BOT_TOKEN || '';
const CHAT_ID = process.env.TELEGRAM_ADMIN_CHAT_ID || '';

export function telegramEnabled(): boolean {
  return !!(TOKEN && CHAT_ID);
}

export function telegramChatLabel(): string | null {
  return telegramEnabled() ? String(CHAT_ID) : null;
}

export async function sendTelegram(text: string): Promise<{ ok: boolean; detail?: string }> {
  if (!telegramEnabled()) {
    return { ok: false, detail: 'TELEGRAM_BOT_TOKEN / TELEGRAM_ADMIN_CHAT_ID belum di-set' };
  }
  try {
    const url = `https://api.telegram.org/bot${TOKEN}/sendMessage`;
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ chat_id: CHAT_ID, text }),
    });
    const j: any = await res.json().catch(() => ({}));
    return { ok: !!j.ok, detail: j.description };
  } catch (e) {
    return { ok: false, detail: String(e) };
  }
}