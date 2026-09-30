import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, writeFile, rm, symlink, realpath } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { once } from 'node:events';
import { readProject, redact } from '../src/project-context.js';
import { createSuggestionService, validateSuggestionRequest } from '../src/prompt-suggestions.js';
import { createServer } from '../src/server.js';

async function fixture(t) {
  const root = await realpath(await mkdtemp(path.join(tmpdir(), 'zazrak-project-')));
  t.after(() => rm(root, { recursive: true, force: true }));
  await mkdir(path.join(root, 'src'));
  await writeFile(path.join(root, 'README.md'), '# A task tracker\nCreate and finish tasks.');
  await writeFile(path.join(root, 'src/tasks.ts'), 'export function tasks() { return []; }');
  return root;
}

const snapshot = { root: '/project', name: 'project', revision: 'a', scannedAt: new Date().toISOString(),
  fileCount: 1, sampledFileCount: 1, partial: false, tree: ['src/tasks.ts'], changedFiles: [], excerpts: [{ path: 'src/tasks.ts', content: 'export const tasks = [];' }] };
const output = { summary: 'A task tracker.', suggestions: [1, 2, 3].map(n => ({ title: `Task ${n}`, prompt: `Implement task ${n} and verify its behavior.`, reason: 'The task list is empty.', files: ['src/tasks.ts'] })) };
const answer = value => new Response(JSON.stringify({ choices: [{ message: { content: JSON.stringify(value) } }] }));

test('Project snapshots include sources and refresh after edits, additions and deletions', async t => {
  const root = await fixture(t);
  const first = await readProject(root);
  assert.equal(first.fileCount, 2);
  await writeFile(path.join(root, 'src/tasks.ts'), 'export function tasks() { return ["new"]; }');
  const edited = await readProject(root);
  assert.notEqual(edited.revision, first.revision);
  assert.ok(edited.excerpts.some(item => item.content.includes('"new"')));
  await writeFile(path.join(root, 'src/new.ts'), 'export const added = true;');
  const added = await readProject(root);
  assert.equal(added.fileCount, 3);
  await rm(path.join(root, 'src/new.ts'));
  assert.equal((await readProject(root)).fileCount, 2);
});

test('Git ignores, secrets, build artifacts, large files and symlinks are excluded', async t => {
  const root = await fixture(t);
  execFileSync('git', ['init', '-q', root]);
  await writeFile(path.join(root, '.gitignore'), 'ignored.ts\n');
  for (const name of ['ignored.ts', '.env', 'credentials.json', 'src/secrets.ts']) await writeFile(path.join(root, name), 'should not read');
  await mkdir(path.join(root, 'dist'));
  await writeFile(path.join(root, 'dist/output.js'), 'generated');
  await writeFile(path.join(root, 'huge.json'), 'a'.repeat(256001));
  await symlink(path.join(root, 'README.md'), path.join(root, 'linked.md'));
  await symlink(path.join(root, 'src'), path.join(root, 'linked-src'));
  const result = await readProject(root);
  assert.deepEqual(result.tree, ['README.md', 'src/tasks.ts']);
  assert.equal(result.excerpts.length, 2);
});

test('Monorepo subfolders stay scoped and paths remain relative', async t => {
  const root = await fixture(t);
  execFileSync('git', ['init', '-q', root]);
  const result = await readProject(path.join(root, 'src'));
  assert.deepEqual(result.tree, ['tasks.ts']);
  assert.deepEqual(result.changedFiles, ['tasks.ts']);
});

test('Snapshots redact common credentials and bound excerpts', async t => {
  const root = await fixture(t);
  await writeFile(path.join(root, 'src/tasks.ts'), `const apiKey = "sensitive-value";\nconst token = "gsk_${'a'.repeat(40)}";\n` + 'x'.repeat(20000));
  const result = await readProject(root);
  const text = JSON.stringify(result.excerpts);
  assert.ok(!text.includes('sensitive-value'));
  assert.ok(!text.includes('gsk_'));
  assert.ok(result.partial);
  assert.ok(text.length < 13000);
  assert.match(redact('https://user:password@example.com'), /REDACTED/);
});

test('Missing credentials explain setup without reading code or calling a provider', async () => {
  const service = createSuggestionService({ apiKey: '', readProjectImpl: () => { throw new Error('must not read'); } });
  assert.equal((await service({ projectPath: '/project' })).status, 'setup');
});

test('Groq receives project evidence and low reasoning; concurrent requests and repeats are cached', async () => {
  let calls = 0, scans = 0;
  const service = createSuggestionService({ apiKey: 'test-key', readProjectImpl: async () => { scans++; return snapshot; }, fetchImpl: async (url, request) => {
    calls++;
    assert.equal(url, 'https://api.groq.com/openai/v1/chat/completions');
    const body = JSON.parse(request.body);
    assert.equal(body.reasoning_effort, 'low');
    assert.equal(body.response_format.type, 'json_schema');
    assert.equal(body.response_format.json_schema.strict, true);
    assert.ok(body.messages[1].content.includes('src/tasks.ts'));
    assert.ok(!body.messages[1].content.includes('private-value'));
    return answer(output);
  } });
  const input = { projectPath: '/project', prompt: 'api_key="private-value"' };
  const [a, b] = await Promise.all([service(input), service(input)]);
  assert.equal(a.status, 'ready'); assert.equal(b.suggestions.length, 3);
  assert.equal(calls, 1); assert.equal(scans, 1);
  assert.equal((await service(input)).cached, true);
  assert.equal(calls, 1);
});

test('Changed code and chat invalidate the cache and rate limits postpone fresh requests', async () => {
  let revision = 'a', time = 0, calls = 0;
  const service = createSuggestionService({ apiKey: 'test-key', now: () => time, readProjectImpl: async () => ({ ...snapshot, revision }), fetchImpl: async () => { calls++; return answer(output); } });
  const input = { projectPath: '/project' };
  await service(input); revision = 'b';
  assert.equal((await service(input)).status, 'waiting');
  time = 16000;
  assert.equal((await service(input)).status, 'ready');
  assert.equal(calls, 2);
  time = 32000;
  await service({ ...input, prompt: 'Next please' });
  assert.equal(calls, 3);
});

test('Invalid, duplicate or ungrounded model output never becomes suggestions', async () => {
  for (const invalid of [{}, { ...output, suggestions: [output.suggestions[0]] },
    { ...output, suggestions: [output.suggestions[0], output.suggestions[0], output.suggestions[2]] },
    { ...output, suggestions: output.suggestions.map(item => ({ ...item, files: ['invented.ts'] })) }]) {
    const service = createSuggestionService({ apiKey: 'test', readProjectImpl: async () => snapshot, fetchImpl: async () => answer(invalid) });
    const result = await service({ projectPath: '/project' });
    assert.equal(result.status, 'error'); assert.deepEqual(result.suggestions, []);
  }
});

test('Proposed new files are not exposed as evidence; existing sampled evidence is retained', async () => {
  const proposed = { ...output, suggestions: output.suggestions.map(item => ({ ...item, files: [...item.files, 'tests/proposed.test.ts'] })) };
  const service = createSuggestionService({ apiKey: 'test', readProjectImpl: async () => snapshot, fetchImpl: async () => answer(proposed) });
  const result = await service({ projectPath: '/project' });
  assert.equal(result.status, 'ready');
  assert.ok(result.suggestions.every(item => item.files.length === 1 && item.files[0] === 'src/tasks.ts'));
});

test('Provider failures hide response bodies and respect rate-limit cooldowns', async () => {
  for (const status of [401, 404, 429, 500]) {
    const service = createSuggestionService({ apiKey: 'test', readProjectImpl: async () => snapshot,
      fetchImpl: async () => new Response('secret-provider-data', { status, headers: { 'retry-after': '60' } }) });
    const result = await service({ projectPath: '/project' });
    assert.ok(!JSON.stringify(result).includes('secret-provider-data'));
    assert.deepEqual(result.suggestions, []);
    if (status === 429) { assert.equal(result.status, 'waiting'); assert.ok(result.retryAfterMs >= 59000); }
  }
});

test('Provider timeout aborts the request and offers automatic recovery', async () => {
  const service = createSuggestionService({ apiKey: 'test', timeoutMs: 10, readProjectImpl: async () => snapshot,
    fetchImpl: async (_url, { signal }) => new Promise((_, reject) => signal.addEventListener('abort', () => reject(new Error('aborted')), { once: true })) });
  const result = await service({ projectPath: '/project' });
  assert.equal(result.status, 'error'); assert.match(result.message, /too long/);
});

test('Suggestion requests validate project scope, prompt and context', () => {
  assert.ok(!validateSuggestionRequest({ projectPath: '/project', prompt: '' }));
  for (const value of [null, [], { projectPath: '.' }, { projectPath: '/project', force: true },
    { projectPath: '/project', prompt: 'a'.repeat(12001) }, { projectPath: '/project', context: 'wrong' }]) assert.ok(validateSuggestionRequest(value));
});

test('Shared fixtures use the published suggestion field names and limits', async () => {
  const read = async name => JSON.parse(await readFile(new URL(`../../contracts/${name}`, import.meta.url), 'utf8'));
  const request = await read('fixtures/suggestions-request.json');
  const fixture = await read('fixtures/suggestions-response.json');
  const schema = await read('suggestions-response.schema.json');
  assert.ok(!validateSuggestionRequest(request));
  const service = createSuggestionService({ apiKey: 'test', readProjectImpl: async () => snapshot, fetchImpl: async () => answer(fixture) });
  const actual = await service(request);
  assert.equal(actual.status, 'ready');
  assert.equal(fixture.suggestions.length, 3);
  assert.deepEqual(Object.keys(actual).sort(), Object.keys(fixture).sort());
  for (const key of Object.keys(actual)) assert.ok(schema.properties[key]);
  for (const key of schema.required) assert.ok(Object.hasOwn(actual, key));
});

test('HTTP suggestions preserve native-only protections and expose structured setup errors', async t => {
  const server = createServer({ mode: 'offline', suggestions: { apiKey: '' } });
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  t.after(() => new Promise(resolve => { server.closeAllConnections(); server.close(resolve); }));
  const url = `http://127.0.0.1:${server.address().port}/suggestions`;
  const request = { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ projectPath: '/project' }) };
  assert.equal((await (await fetch(url, request)).json()).status, 'setup');
  assert.equal((await fetch(url, { ...request, headers: { ...request.headers, Origin: 'https://untrusted.test' } })).status, 403);
  assert.equal((await fetch(url, { ...request, body: '{"projectPath":"relative"}' })).status, 400);
  assert.equal((await fetch(url, { ...request, body: '{broken' })).status, 400);
});
