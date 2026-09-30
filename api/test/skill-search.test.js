import test from 'node:test';
import assert from 'node:assert/strict';
import { analyze } from '../src/analyze.js';
import { createServer, validateRequest } from '../src/server.js';
import { librarySummary } from '../src/skill-library.js';
import { knowledgeLibrary } from '../eval/knowledge.js';
import { parseFindArgs, formatMatches } from '../../scripts/find-skills.js';
import { hookResponse } from '../../scripts/claude-hook.js';

const prompt = 'Fix Swift Sendable actor isolation.';
const options = { mode: 'knowledge', library: knowledgeLibrary, fetchImpl: () => assert.fail('Search must stay local') };

test('Best match is explicit, stable under input order, and recalculated before limiting and deduplication', async () => {
  const first = await analyze({ prompt, app: 'Codex', maxSkills: 1 }, options);
  assert.equal(first.skills[0].name, 'swift-concurrency');
  assert.equal(first.meta.bestSkillId, first.skills[0].id);
  const reversed = await analyze({ prompt, app: 'Codex' }, { ...options, library: { ...knowledgeLibrary, skills: [...knowledgeLibrary.skills].reverse() } });
  assert.equal(reversed.meta.bestSkillId, first.meta.bestSkillId);
  const filtered = await analyze({ prompt, app: 'Codex', maxSkills: 1, filters: { q: 'swift-concurrency-expert' } }, options);
  assert.equal(filtered.skills[0].name, 'swift-concurrency-expert');
  assert.equal(filtered.meta.bestSkillId, filtered.skills[0].id);
});

test('Empty filters cannot force irrelevant skills; opt-out and zero limit have no best match', async () => {
  for (const request of [{ prompt: 'Say hello.', filters: { q: 'swift' } }, { prompt, filters: { provenance: 'public-import' } },
    { prompt, maxSkills: 0 }, { prompt: 'Optimize React performance without any skills.' }]) {
    const result = await analyze(request, options);
    assert.deepEqual(result.skills, []);
    assert.equal(result.meta.bestSkillId, null);
  }
});

test('Library combines availability, exact source, scope, purpose, and unordered search terms without bodies', () => {
  const result = librarySummary(knowledgeLibrary, { provenance: 'installed', source: 'evaluation FIXTURE', scope: 'swiftui', purpose: 'performance', q: 'slow optimize' });
  assert.deepEqual(result.skills.map(skill => skill.name), ['swiftui-performance-audit']);
  assert.equal(result.count, 1);
  assert.equal(result.totalCount, knowledgeLibrary.skills.length);
  assert.equal(result.publicCount, 0);
  assert.equal(result.skills[0].content, undefined);
});

test('CLI shares ranking and names the best match, with invalid flags and filters rejected', async () => {
  const { request, json } = parseFindArgs([prompt, '--app', 'Codex', '--scope', 'swift', '--limit', '1', '--json']);
  assert.equal(json, true);
  const result = await analyze(request, options);
  assert.match(formatMatches(result), /^Best match: swift-concurrency \(\d+\/100\)\nSource: file:/);
  assert.match(formatMatches(await analyze({ prompt: 'Say hello.' }, options)), /^No eligible skill/);
  for (const args of [[], [prompt, '--bogus'], [prompt, '--limit', '99'], [prompt, '--provenance', 'nope']]) assert.throws(() => parseFindArgs(args));
  for (const filters of [null, [], { q: '' }, { q: 'x'.repeat(201) }, { source: 1 }, { unexpected: 'x' }]) assert.ok(validateRequest({ prompt, filters }));
});

test('Claude hook asks to mention exactly one best match with source and no skill body', () => {
  const context = hookResponse({ hook_event_name: 'UserPromptSubmit', prompt: 'Improve SwiftUI accessibility and performance.' }, knowledgeLibrary).hookSpecificOutput.additionalContext;
  assert.match(context, /Mention the bestMatch skill by name and source/);
  const rows = context.split('\n').slice(1).map(line => JSON.parse(line));
  assert.equal(rows.filter(row => row.bestMatch).length, 1);
  assert.equal(rows[0].bestMatch, true);
  assert.ok(rows[0].source.startsWith('file:'));
  assert.ok(rows.every(row => !Object.hasOwn(row, 'content')));
});

test('HTTP browse filters and analysis return the same eligible scope and reject malformed filters', async t => {
  const server = createServer(options);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => { server.close(resolve); server.closeAllConnections(); }));
  const base = `http://127.0.0.1:${server.address().port}`;
  const response = await fetch(`${base}/skills?scope=swiftui&purpose=performance&provenance=installed`);
  assert.equal(response.status, 200);
  const summary = await response.json();
  assert.deepEqual(summary.skills.map(skill => skill.name), ['swiftui-performance-audit']);
  for (const query of ['q=', 'scope=a&scope=b', 'unknown=yes', 'provenance=bogus']) assert.equal((await fetch(`${base}/skills?${query}`)).status, 400);
  assert.equal((await fetch(`${base}/skills?q=swift`, { headers: { Origin: 'https://example.com' } })).status, 403);
  const filtered = await fetch(`${base}/analyze`, { method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ prompt, app: 'Codex', filters: { q: 'swift-concurrency-expert' }, maxSkills: 1 }) });
  assert.equal(filtered.status, 200);
  assert.equal((await filtered.json()).meta.bestSkillId, 'installed/swift-concurrency-expert');
});
