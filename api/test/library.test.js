import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, rm, symlink } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { importSkills, parseSkill, saveLibrary, readLibrary, librarySummary, publicSources } from '../src/skill-library.js';
import { createServer } from '../src/server.js';

const markdown = (name, description = 'Swift actor isolation and concurrency.') => `---\nname: ${name}\ndescription: ${description}\n---\n# Instructions\nThese instructions are never executed by Preflight.\n`;
async function temporary(t) {
  const directory = await mkdtemp(join(tmpdir(), 'preflight-import-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  return directory;
}
async function writeSkill(root, directory, content) {
  await mkdir(join(root, directory), { recursive: true });
  await writeFile(join(root, directory, 'SKILL.md'), content);
}

test('Metadata parser supports quoted and folded descriptions without evaluating YAML', () => {
  assert.deepEqual(parseSkill(markdown('swift-test', '"Swift tests."')), { name: 'swift-test', description: 'Swift tests.' });
  assert.equal(parseSkill(markdown('swift-test', '>\n  Swift actor isolation\n  and concurrency.')).description, 'Swift actor isolation and concurrency.');
  assert.throws(() => parseSkill('Missing metadata'));
  assert.throws(() => parseSkill(markdown('../../escape')));
  assert.throws(() => parseSkill(markdown('bad', '!execute command')));
  assert.throws(() => parseSkill('---\nname: incomplete\n---\n'));
});

test('Import deduplicates copies, skips malformed and oversized files, and preserves content privately', async t => {
  const directory = await temporary(t);
  const content = markdown('swift-concurrency');
  await writeSkill(directory, 'a', content);
  await writeSkill(directory, 'a/skills/copy', content);
  await writeSkill(directory, 'broken', 'No metadata');
  await writeSkill(directory, 'oversized', content + 'x'.repeat(256 * 1024));
  const library = await importSkills({ roots: [directory, directory], includePublic: false });
  assert.equal(library.skills.length, 1);
  assert.equal(library.duplicates, 1);
  assert.equal(library.warnings.length, 2);
  assert.equal(library.skills[0].content, content);
  assert.equal(library.skills[0].provenance, 'installed');
  assert.ok(library.skills[0].url.startsWith('file:'));
  const path = join(directory, 'index/skills.json');
  await saveLibrary(library, path);
  assert.deepEqual(await readLibrary(path), library);
  const summary = librarySummary(library);
  assert.equal(summary.installedCount, 1);
  assert.ok(!JSON.stringify(summary).includes('These instructions are never executed'));
});

test('Nested symlinks are not followed, and a removed skill disappears on refresh', async t => {
  const directory = await temporary(t);
  await writeSkill(directory, 'outside', markdown('outside'));
  await writeSkill(directory, 'root/inside', markdown('inside'));
  await symlink(join(directory, 'outside'), join(directory, 'root/link'));
  let library = await importSkills({ roots: [join(directory, 'root')], includePublic: false });
  assert.deepEqual(library.skills.map(s => s.name), ['inside']);
  await rm(join(directory, 'root/inside'), { recursive: true });
  library = await importSkills({ roots: [join(directory, 'root')], includePublic: false, previous: library });
  assert.deepEqual(library.skills, []);
});

test('Public import uses bounded configured GitHub sources and retains previous snapshots on outage', async () => {
  let calls = 0;
  const imported = await importSkills({ roots: [], fetchImpl: async (url, options) => {
    assert.equal(new URL(url).hostname, 'raw.githubusercontent.com');
    assert.equal(options.redirect, 'error');
    return new Response(markdown(`public-skill-${++calls}`, 'Public testing guidance.'));
  } });
  assert.equal(imported.skills.length, publicSources.length);
  assert.ok(imported.skills.every(s => s.provenance === 'public-import' && s.hash.length === 64));
  const failed = await importSkills({ roots: [], previous: imported, fetchImpl: async () => { throw new Error('Offline'); } });
  assert.equal(failed.skills.length, imported.skills.length);
  assert.equal(failed.warnings.length, publicSources.length);
  const oversized = await importSkills({ roots: [], fetchImpl: async () => new Response('x'.repeat(256 * 1024 + 1)) });
  assert.equal(oversized.skills.length, 0);
});

test('Library HTTP endpoint exposes metadata, and remote origins and configurable roots are rejected', async t => {
  const library = await importSkills({ roots: [], includePublic: false });
  const server = createServer({ mode: 'hybrid', library });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => { server.close(resolve); server.closeAllConnections(); }));
  const base = `http://127.0.0.1:${server.address().port}`;
  assert.equal((await (await fetch(`${base}/skills`)).json()).count, 0);
  assert.equal((await fetch(`${base}/skills`, { headers: { Origin: 'https://example.com' } })).status, 403);
  assert.equal((await fetch(`${base}/skills/import`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{"roots":["/"]}' })).status, 400);
  assert.equal((await fetch(`${base}/skills/import`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: 'x'.repeat(1025) })).status, 413);
});
