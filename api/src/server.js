import http from 'node:http';
import { pathToFileURL } from 'node:url';
import { analyze } from './analyze.js';

export function validateRequest(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return 'Expected a JSON object.';
  if (Object.keys(value).some(k => !['prompt', 'app', 'maxSkills'].includes(k))) return 'Unknown request field.';
  if (typeof value.prompt !== 'string' || !value.prompt.trim() || value.prompt.length > 12000) return 'Prompt must contain 1–12000 characters.';
  if (value.app !== undefined && (typeof value.app !== 'string' || value.app.length > 200)) return 'App must be a string of at most 200 characters.';
  if (value.maxSkills !== undefined && (!Number.isInteger(value.maxSkills) || value.maxSkills < 0 || value.maxSkills > 3)) return 'maxSkills must be 0–3.';
  return null;
}

export function createServer(options = {}) {
  return http.createServer({ requestTimeout: 10000, headersTimeout: 10000 }, async (req, res) => {
    const json = (status, payload) => {
      res.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' });
      res.end(JSON.stringify(payload));
    };
    const fail = (status, code, message) => json(status, { error: { code, message } });
    // Native-only local API: reject browser origins before reading any prompt.
    if (req.headers.origin || !/^(127\.0\.0\.1|localhost)(:\d+)?$/.test(req.headers.host ?? '')) return fail(403, 'FORBIDDEN', 'Use the native client or local CLI.');
    if (req.method === 'GET' && req.url === '/health') return json(200, { status: 'ok', schemaVersion: '1.0' });
    if (req.method !== 'POST' || req.url !== '/analyze') return fail(404, 'NOT_FOUND', 'Use POST /analyze.');
    if (!(req.headers['content-type'] ?? '').toLowerCase().startsWith('application/json')) return fail(415, 'CONTENT_TYPE', 'Use application/json.');
    try {
      const chunks = [];
      let size = 0;
      for await (const chunk of req) {
        size += chunk.length;
        if (size > 65536) { fail(413, 'TOO_LARGE', 'Request exceeds 64 KiB.'); return; }
        chunks.push(chunk);
      }
      let payload;
      try { payload = JSON.parse(Buffer.concat(chunks).toString('utf8')); }
      catch { return fail(400, 'INVALID_JSON', 'Body must be valid JSON.'); }
      const error = validateRequest(payload);
      if (error) return fail(400, 'INVALID_REQUEST', error);
      json(200, await analyze({ ...payload, prompt: payload.prompt.trim() }, options));
    } catch {
      if (!res.headersSent) fail(500, 'INTERNAL_ERROR', 'Analysis failed. Please try again.');
    }
  });
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try { process.loadEnvFile('.env'); } catch (error) { if (error.code !== 'ENOENT') throw error; }
  const port = Number(process.env.PORT ?? 8787);
  const timeout = Number(process.env.SKILLS_TIMEOUT_MS ?? 2500);
  const mode = process.env.SKILLS_MODE ?? 'live';
  if (!Number.isInteger(port) || port < 1 || port > 65535 || !Number.isFinite(timeout) || timeout < 100 || timeout > 10000 || !['live', 'offline'].includes(mode)) throw new Error('Invalid PORT, SKILLS_TIMEOUT_MS, or SKILLS_MODE.');
  const server = createServer({ mode, timeout });
  server.on('error', error => { console.error(`Cannot start Preflight: ${error.message}`); process.exitCode = 1; });
  server.listen(port, '127.0.0.1', () => console.log(`Preflight API: http://127.0.0.1:${port} (${mode})`));
  for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => server.close());
}
