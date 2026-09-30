import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { analyze, classify, discover, normalizeSkill } from '../src/analyze.js';
import { createServer } from '../src/server.js';
import { criterionCandidates } from '../eval/criteria.js';
import { knowledgeLibrary } from '../eval/knowledge.js';

const read = async name => JSON.parse(await readFile(new URL(`../../${name}`, import.meta.url)));
const example = { prompt: 'Optimize this Next.js page. It is slow when rendering 500 products.', app: 'Cursor', maxSkills: 3 };

// Assertions for the JSON Schema features used by our contract, not a general schema engine.
function matchesSchema(value, schema) {
  if (schema.const !== undefined) assert.deepEqual(value, schema.const);
  if (schema.enum) assert.ok(schema.enum.includes(value), `Unexpected enum value: ${value}`);
  if (schema.type) {
    const types = [].concat(schema.type);
    assert.ok(types.some(type => type === 'null' ? value === null : type === 'integer' ? Number.isInteger(value) : type === 'array' ? Array.isArray(value) : type === 'object' ? value !== null && !Array.isArray(value) && typeof value === 'object' : typeof value === type));
  }
  if (typeof value === 'number') {
    if (schema.minimum !== undefined) assert.ok(value >= schema.minimum);
    if (schema.maximum !== undefined) assert.ok(value <= schema.maximum);
  }
  if (typeof value === 'string') {
    if (schema.minLength !== undefined) assert.ok(value.length >= schema.minLength);
    if (schema.maxLength !== undefined) assert.ok(value.length <= schema.maxLength);
    if (schema.pattern) assert.match(value, new RegExp(schema.pattern));
    if (schema.format === 'uri') assert.doesNotThrow(() => new URL(value));
  }
  if (Array.isArray(value)) {
    if (schema.maxItems !== undefined) assert.ok(value.length <= schema.maxItems);
    for (const item of value) matchesSchema(item, schema.items);
  }
  if (schema.properties) {
    for (const key of schema.required) assert.ok(Object.hasOwn(value, key), `Missing ${key}`);
    for (const [key, item] of Object.entries(value)) {
      assert.ok(schema.properties[key], `Unexpected ${key}`);
      matchesSchema(item, schema.properties[key]);
    }
  }
}

test('React performance recommends a relevant skill, without unrelated database skills', async () => {
  const result = await analyze(example, { mode: 'offline' });
  assert.equal(result.skills[0].name, 'vercel-react-best-practices');
  assert.ok(!result.skills.some(s => s.name.includes('postgres')));
  assert.equal(result.meta.source, 'catalog');
  assert.equal(result.effort.level, 'medium');
  matchesSchema(result, await read('contracts/analyze-response.schema.json'));
});

test('No skill is a valid result; zero limit is respected', async () => {
  assert.deepEqual((await analyze({ prompt: 'Say hello.' })).skills, []);
  assert.deepEqual((await analyze({ ...example, maxSkills: 0 }, { mode: 'offline' })).skills, []);
});

test('Raw prompt secrets are never search queries', () => {
  const { queries } = classify('Fix React performance. Secret project starship and token sk-secret123.');
  assert.deepEqual(queries, ['react performance', 'frontend performance']);
  assert.ok(!JSON.stringify(queries).includes('secret'));
});

test('Live search deduplicates, rejects invalid records and respects query limits', async () => {
  const good = { source: 'vercel-labs/agent-skills', skillId: 'vercel-react-best-practices', installs: 1234 };
  let calls = 0;
  const result = await discover(['react performance', 'nextjs performance'], { fetchImpl: async url => {
    calls++;
    assert.equal(url.hostname, 'skills.sh');
    assert.equal(url.pathname, '/api/search');
    assert.equal(url.searchParams.get('limit'), '8');
    return new Response(JSON.stringify({ skills: [good, good, { ...good, source: 'https://evil.test' }, { ...good, isDuplicate: true }] }));
  } });
  assert.equal(calls, 2);
  assert.equal(result.candidates.length, 1);
  assert.equal(result.source, 'skills.sh');
  assert.equal(normalizeSkill({ source: 'ok/repo', skillId: '$(touch pwned)' }), null);
});

test('Upstream failure falls back explicitly; a successful empty search stays empty', async () => {
  const failed = await discover(['react'], { fetchImpl: async () => { throw new Error('timeout'); } });
  assert.equal(failed.source, 'catalog');
  assert.ok(failed.warnings.length > 0);
  const empty = await discover(['react'], { fetchImpl: async () => new Response('{"skills":[]}') });
  assert.equal(empty.source, 'skills.sh');
  assert.deepEqual(empty.candidates, []);
});

test('Partial search failure preserves successful results and warns', async () => {
  const result = await discover(['react', 'broken'], { fetchImpl: async url => {
    if (url.searchParams.get('q') === 'broken') return new Response('', { status: 503 });
    return new Response('{"skills":[{"source":"a/b","name":"react-testing"}]}');
  } });
  assert.equal(result.candidates.length, 1);
  assert.equal(result.source, 'skills.sh');
  assert.equal(result.warnings.length, 1);
});

test('Shared request/response fixtures conform and the Swift demo is identical', async () => {
  const request = await read('contracts/fixtures/analyze-request.json');
  const response = await read('contracts/fixtures/analyze-response.json');
  matchesSchema(request, await read('contracts/analyze-request.schema.json'));
  matchesSchema(response, await read('contracts/analyze-response.schema.json'));
  assert.deepEqual(response, await read('macos/Sources/Preflight/Resources/demo-response.json'));
  const imported = await analyze({ prompt: 'Fix Swift actor isolation.' }, { mode: 'installed', library: { skills: criterionCandidates, warnings: [] } });
  matchesSchema(imported, await read('contracts/analyze-response.schema.json'));
  const studied = await analyze({ prompt: 'Fix Swift Sendable actor isolation.', app: 'Claude Code' }, { mode: 'knowledge', library: knowledgeLibrary });
  assert.equal(studied.skills[0].evaluation.criteria.length, 12);
  matchesSchema(studied, await read('contracts/analyze-response.schema.json'));
});

test('HTTP API validates bodies and errors; rejects browser origins', async t => {
  const server = createServer({ mode: 'offline' });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => { server.close(resolve); server.closeAllConnections(); }));
  const base = `http://127.0.0.1:${server.address().port}`;
  const post = (body, headers = {}) => fetch(`${base}/analyze`, { method: 'POST', headers: { 'Content-Type': 'application/json', ...headers }, body });
  assert.equal((await fetch(`${base}/health`)).status, 200);
  const success = await post(JSON.stringify(example));
  assert.equal(success.status, 200);
  matchesSchema(await success.json(), await read('contracts/analyze-response.schema.json'));
  for (const bad of ['{}', 'null', '{', '{"prompt":" "}', '{"prompt":42}', '{"prompt":"Hi","maxSkills":4}', '{"prompt":"Hi","unexpected":true}']) {
    const response = await post(bad);
    assert.equal(response.status, 400);
    matchesSchema(await response.json(), await read('contracts/error.schema.json'));
  }
  assert.equal((await post(JSON.stringify({ prompt: 'a'.repeat(12001) }))).status, 400);
  assert.equal((await post(JSON.stringify({ prompt: 'a'.repeat(200000) }))).status, 413);
  assert.equal((await post(JSON.stringify(example), { Origin: 'https://evil.test' })).status, 403);
  assert.equal((await post(JSON.stringify(example), { 'Content-Type': 'text/plain' })).status, 415);
  assert.equal((await fetch(`${base}/missing`)).status, 404);
});
