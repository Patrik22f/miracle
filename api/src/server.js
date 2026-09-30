import http from 'node:http';
import { pathToFileURL } from 'node:url';
import { analyze } from './analyze.js';
import { createLibraryStore, createLocalLibraryStore, importSkills, saveLibrary, librarySummary } from './skill-library.js';
import { validateContext } from './task-context.js';
import { validateSkillFilters } from './skill-filters.js';
import { createSuggestionService, validateSuggestionRequest } from './prompt-suggestions.js';

export function validateRequest(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return 'Expected a JSON object.';
  if (Object.keys(value).some(k => !['prompt', 'app', 'maxSkills', 'context', 'filters'].includes(k))) return 'Unknown request field.';
  if (typeof value.prompt !== 'string' || !value.prompt.trim() || value.prompt.length > 12000) return 'Prompt must contain 1–12000 characters.';
  if (value.app !== undefined && (typeof value.app !== 'string' || value.app.length > 200)) return 'App must be a string of at most 200 characters.';
  if (value.maxSkills !== undefined && (!Number.isInteger(value.maxSkills) || value.maxSkills < 0 || value.maxSkills > 8)) return 'maxSkills must be 0–8.';
  return validateSkillFilters(value.filters) || validateContext(value.context);
}

export function createServer(options = {}) {
  let importing;
  const suggest = createSuggestionService(options.suggestions);
  const store = options.libraryPath ? createLibraryStore(options.libraryPath) : createLocalLibraryStore();
  const currentLibrary = () => options.library ? Promise.resolve(options.library) : store();
  return http.createServer({ requestTimeout: 10000, headersTimeout: 10000 }, async (req, res) => {
    const json = (status, payload) => {
      res.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' });
      res.end(JSON.stringify(payload));
    };
    const fail = (status, code, message) => json(status, { error: { code, message } });
    // Native-only local API: reject browser origins before reading any prompt.
    if (req.headers.origin || !/^(127\.0\.0\.1|localhost)(:\d+)?$/.test(req.headers.host ?? '')) return fail(403, 'FORBIDDEN', 'Use the native client or local CLI.');
    if (req.method === 'GET' && req.url === '/health') return json(200, { status: 'ok', schemaVersion: '1.0', mode: options.mode ?? 'knowledge', contextAware: (options.mode ?? 'knowledge') === 'knowledge' });
    if (req.method === 'GET' && (req.url === '/skills' || req.url.startsWith('/skills?'))) {
      const params = new URL(req.url, 'http://localhost').searchParams;
      const filters = Object.fromEntries(params);
      const error = validateSkillFilters(filters);
      if (error || [...params.keys()].some(key => params.getAll(key).length > 1)) return fail(400, 'INVALID_REQUEST', error ?? 'Repeated skill filter.');
      try { return json(200, librarySummary(await currentLibrary(), filters)); }
      catch { return fail(500, 'LIBRARY_ERROR', 'Could not read the skill library. Run npm run skills:import.'); }
    }
    if (req.method === 'POST' && req.url === '/skills/import') {
      if (!(req.headers['content-type'] ?? '').toLowerCase().startsWith('application/json')) return fail(415, 'CONTENT_TYPE', 'Use application/json.');
      try {
        const chunks = []; let size = 0;
        for await (const chunk of req) {
          size += chunk.length;
          if (size > 1024) return fail(413, 'TOO_LARGE', 'Import request exceeds 1 KiB.');
          chunks.push(chunk);
        }
        const body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
        if (!body || Array.isArray(body) || typeof body !== 'object' || Object.keys(body).length) return fail(400, 'INVALID_REQUEST', 'Import accepts an empty object; configure roots locally.');
      } catch { return fail(400, 'INVALID_JSON', 'Body must be an empty JSON object.'); }
      // Roots and URLs come only from the locally configured library, never an HTTP body.
      if (!importing) importing = (async () => {
        const previous = await currentLibrary();
        const library = await importSkills({ roots: previous.roots, includePublic: previous.includePublic,
          publicProvider: previous.publicProvider, discover: previous.discover,
          searchQueries: previous.searchQueries, searchOwner: previous.searchOwner, previous });
        await saveLibrary(library, options.libraryPath);
        return library;
      })().finally(() => { importing = null; });
      try { return json(200, librarySummary(await importing)); }
      catch { return fail(500, 'IMPORT_ERROR', 'Skill import failed. Run npm run skills:import to inspect it.'); }
    }
    if (req.method !== 'POST' || !['/analyze', '/suggestions'].includes(req.url)) return fail(404, 'NOT_FOUND', 'Use POST /analyze or /suggestions.');
    if (!(req.headers['content-type'] ?? '').toLowerCase().startsWith('application/json')) return fail(415, 'CONTENT_TYPE', 'Use application/json.');
    try {
      const chunks = [];
      let size = 0;
      for await (const chunk of req) {
        size += chunk.length;
        if (size > 196608) { fail(413, 'TOO_LARGE', 'Request exceeds 192 KiB.'); return; }
        chunks.push(chunk);
      }
      let payload;
      try { payload = JSON.parse(Buffer.concat(chunks).toString('utf8')); }
      catch { return fail(400, 'INVALID_JSON', 'Body must be valid JSON.'); }
      const error = req.url === '/suggestions' ? validateSuggestionRequest(payload) : validateRequest(payload);
      if (error) return fail(400, 'INVALID_REQUEST', error);
      if (req.url === '/suggestions') {
        try { return json(200, await suggest(payload)); }
        catch { return fail(422, 'PROJECT_UNAVAILABLE', 'Could not read this project. Choose an accessible project folder.'); }
      }
      const mode = options.mode ?? 'knowledge';
      const library = ['knowledge', 'hybrid', 'installed'].includes(mode) ? await currentLibrary() : options.library;
      json(200, await analyze({ ...payload, prompt: payload.prompt.trim() }, { ...options, mode, library }));
    } catch {
      if (!res.headersSent) fail(500, 'INTERNAL_ERROR', 'Analysis failed. Please try again.');
    }
  });
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try { process.loadEnvFile('.env'); } catch (error) { if (error.code !== 'ENOENT') throw error; }
  const port = Number(process.env.PORT ?? 8787);
  const timeout = Number(process.env.SKILLS_TIMEOUT_MS ?? 2500);
  const mode = process.env.SKILLS_MODE ?? 'knowledge';
  if (!Number.isInteger(port) || port < 1 || port > 65535 || !Number.isFinite(timeout) || timeout < 100 || timeout > 10000 || !['knowledge', 'hybrid', 'installed', 'live', 'offline'].includes(mode)) throw new Error('Invalid PORT, SKILLS_TIMEOUT_MS, or SKILLS_MODE.');
  const server = createServer({ mode, timeout });
  server.on('error', error => { console.error(`Cannot start Preflight: ${error.message}`); process.exitCode = 1; });
  server.listen(port, '127.0.0.1', () => console.log(`Preflight API: http://127.0.0.1:${port} (${mode})`));
  for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => server.close());
}
