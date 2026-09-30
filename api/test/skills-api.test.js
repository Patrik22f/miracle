import test from 'node:test';
import assert from 'node:assert/strict';
import { createSkillsAPI, apiSeeds } from '../src/skills-api.js';
import { importSkills } from '../src/skill-library.js';
const id = 'anthropics/skills/pdf';
const content = '---\nname: pdf\ndescription: Create PDF files.\n---\n# PDF\nCreate PDF files and verify pages.';
const detail = { id, source: 'anthropics/skills', slug: 'pdf', hash: 'upstream-snapshot', installs: 42, files: [{ path: 'SKILL.md', contents: content }] };
const apiWith = payload => createSkillsAPI({ tokenProvider: () => 'test-only-token', fetchImpl: async () => Response.json(payload) });

test('Official adapter uses v1 details, exact identity, refreshed token per call and no redirects', async () => {
  let serial = 0;
  const api = createSkillsAPI({ tokenProvider: () => `token-${++serial}`, fetchImpl: async (url, options) => {
    assert.equal(url, 'https://skills.sh/api/v1/skills/anthropics/skills/pdf');
    assert.equal(options.headers.Authorization, `Bearer token-${serial}`);
    assert.equal(options.redirect, 'error'); assert.ok(options.signal);
    return Response.json(detail);
  } });
  assert.equal((await api.detail(id)).content, content);
  await api.detail(id); assert.equal(serial, 2);
  await assert.rejects(api.detail('../../private'), /Invalid skill ID/);
});

test('Missing authentication does not use the legacy public endpoint', async () => {
  const api = createSkillsAPI({ tokenProvider: () => '', fetchImpl: () => assert.fail('No unauthenticated fallback') });
  await assert.rejects(api.detail(id), /Vercel OIDC/);
});

test('Detail validation rejects path traversal, duplicate files, missing body and wrong identity', async () => {
  for (const bad of [{ ...detail, id: 'other/skills/pdf' }, { ...detail, files: null }, { ...detail, files: [] },
    { ...detail, files: [...detail.files, ...detail.files] },
    ...['../secret', '/etc/passwd', 'scripts\\bad', 'scripts/./bad'].map(path => ({ ...detail, files: [...detail.files, { path, contents: 'x' }] }))]) {
    await assert.rejects(apiWith(bad).detail(id));
  }
  await assert.rejects(createSkillsAPI({ tokenProvider: () => 'token', fetchImpl: async () => new Response('x'.repeat(2 * 1024 * 1024 + 1)) }).detail(id), /2 MiB/);
});

test('Curated discovery is allowlisted, bounded and deduplicated', async () => {
  const api = apiWith({ data: [{ skills: [{ id, source: 'anthropics/skills' }, { id, source: 'anthropics/skills' },
    { id: 'evil/skills/pdf', source: 'evil/skills' }, { id: 'anthropics/skills/fork', source: 'anthropics/skills', isDuplicate: true }] }] });
  assert.deepEqual(await api.curatedIDs(), [id]);
});

test('Import caps concurrency at four and retains exact prior versions on API failure', async () => {
  let active = 0, peak = 0;
  const api = { async detail(skillID) {
    peak = Math.max(peak, ++active);
    await new Promise(resolve => setTimeout(resolve, 2)); active--;
    return { ...detail, id: skillID, source: skillID.split('/').slice(0, 2).join('/'),
      content: content.replace('name: pdf', `name: ${skillID.split('/').at(-1)}`) };
  } };
  const library = await importSkills({ roots: [], publicProvider: 'skills-api', api });
  assert.equal(library.skills.length, apiSeeds.length); assert.ok(peak <= 4);
  assert.ok(library.skills.every(skill => skill.apiId && skill.hash.length === 64 && skill.files.length === 1));
  assert.ok(!JSON.stringify(library).includes('test-only-token'));
  const outage = await importSkills({ roots: [], publicProvider: 'skills-api', previous: library, api: { detail: async () => { throw new Error('Expired bearer secret'); } } });
  assert.deepEqual(outage.skills, library.skills);
  assert.equal(outage.warnings.length, apiSeeds.length);
  assert.ok(!JSON.stringify(outage).includes('bearer secret'));
});

test('Curated outage preserves previously discovered candidates beyond the seed set', async () => {
  const extraID = 'anthropics/skills/extra';
  const old = { id: extraID, apiId: extraID, name: 'extra', description: 'Create PDF files.', content: content.replace('name: pdf', 'name: extra'), source: 'anthropics/skills', provenance: 'public-import', url: 'https://skills.sh/' + extraID };
  const library = await importSkills({ roots: [], publicProvider: 'skills-api', discover: true, previous: { skills: [old] },
    api: { curatedIDs: async () => { throw new Error('Offline'); }, detail: async () => { throw new Error('Offline'); } } });
  assert.ok(library.skills.some(skill => skill.apiId === extraID));
});
