const positions = {
  install_click: ['hero', 'nav', 'hero_download', 'install_download', 'download'],
  install_copy: ['install'],
  source_click: ['header', 'hero', 'footer'],
};
const hosts = new Set(['codex-cub.edgewavelabs.ai', 'codex-usage.edgewavelabs.ai', 'codex-usage-3bp.pages.dev', 'localhost', '127.0.0.1']);
const reply = (status) => new Response(null, { status, headers: { 'Cache-Control': 'no-store' } });

export async function onRequest({ request, env }) {
  if (request.method !== 'POST') return reply(405);
  const url = new URL(request.url);
  // Require same-origin evidence. A bad Origin must never fall back to Referer.
  const origin = request.headers.get('Origin');
  let source = origin;
  if (origin === null) {
    try { source = new URL(request.headers.get('Referer')).origin; } catch { return reply(403); }
  }
  if (!hosts.has(url.hostname) || source !== url.origin) return reply(403);
  if (request.headers.get('Content-Type')?.split(';')[0] !== 'application/json') return reply(415);
  if (!request.body) return reply(400);
  const reader = request.body.getReader();
  let length = 0;
  const chunks = [];
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    length += value.byteLength;
    if (length > 512) { await reader.cancel(); return reply(413); }
    chunks.push(value);
  }
  let event;
  try { event = JSON.parse(await new Blob(chunks).text()); } catch { return reply(400); }
  if (!event || !Object.hasOwn(positions, event.event) || !positions[event.event].includes(event.position)
      || !['zh', 'en'].includes(event.language)) return reply(400);
  if (!env.ANALYTICS_DB) return reply(503);
  try {
    // UTC daily totals only; no raw requests or visitor identifiers are stored.
    await env.ANALYTICS_DB.prepare(`
      INSERT INTO event_counts (day, event, position, language, count)
      VALUES (?, ?, ?, ?, 1)
      ON CONFLICT (day, event, position, language) DO UPDATE SET count = count + 1
    `).bind(new Date().toISOString().slice(0, 10), event.event, event.position, event.language).run();
    return reply(204);
  } catch { return reply(503); }
}
