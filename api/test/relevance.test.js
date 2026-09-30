import test from 'node:test';
import assert from 'node:assert/strict';
import { evaluate } from '../eval/relevance.js';
import { analyze, classify, normalizeSkill, rank } from '../src/analyze.js';

for (const result of evaluate()) {
  test(`Relevance: ${result.id}`, () => {
    assert.deepEqual(result.missing, [], 'Required useful skills are missing');
    assert.deepEqual(result.unexpected, [], 'Unrelated skills were recommended');
  });
}

const skill = (name, installs = 1, source = 'evaluation/fixtures') => normalizeSkill({ source, skillId: name, installs });

test('A common word or ordinary question does not trigger programming advice', async () => {
  for (const prompt of ['What should I do next?', 'Why is the sky blue?', 'Translate the next sentence into Czech.']) {
    const result = await analyze({ prompt }, { fetchImpl: () => { assert.fail('No public search is needed'); } });
    assert.deepEqual(result.skills, []);
    assert.equal(result.meta.source, 'none');
  }
});

test('Repository names and popularity cannot supply missing relevance', () => {
  const result = rank([
    skill('authentication', Number.MAX_SAFE_INTEGER, 'react/performance'),
    skill('react-best-practices', Number.MAX_SAFE_INTEGER),
    skill('react-performance', 1),
  ], classify('Optimize a slow React product list.'));
  assert.deepEqual(result.map(s => s.name), ['react-performance']);
  assert.match(result[0].reason, /React.*performance/);
});

test('Live unknown skills must match purpose as well as platform', async () => {
  const result = await analyze({ prompt: 'Optimize this Next.js product list.' }, { fetchImpl: async () => new Response(JSON.stringify({ skills: [
    { source: 'clerk/skills', skillId: 'clerk-nextjs-patterns', installs: 999999 },
    { source: 'evaluation/fixtures', skillId: 'nextjs-performance', installs: 1 },
    { source: 'evaluation/fixtures', skillId: 'nextjs-deployment', installs: 999999 },
  ] })) });
  assert.equal(result.meta.source, 'skills.sh');
  assert.deepEqual(result.skills.map(s => s.name), ['nextjs-performance']);
});

test('Native and browser React tasks have distinct search topics', () => {
  assert.deepEqual(classify('Optimize React Native rendering.').queries, ['react native performance']);
  assert.deepEqual(classify('Optimize Next JS rendering.').queries, ['nextjs performance', 'react performance']);
  assert.deepEqual(classify('Add Clerk authentication to Next.js. Private key abc-secret.').queries, ['nextjs authentication', 'clerk authentication']);
});

test('More relevant skills win over popularity, duplicates, and candidate order', () => {
  const candidates = [skill('react-performance', Number.MAX_SAFE_INTEGER), skill('react-performance-debugging', 1), skill('react-performance-debugging', 1)];
  const task = classify('Fix a slow React app.');
  const names = rows => rank(rows, task).map(s => s.name);
  assert.deepEqual(names(candidates), ['react-performance-debugging', 'react-performance']);
  assert.deepEqual(names([...candidates].reverse()), names(candidates));
  assert.deepEqual(rank(candidates, task, 0), []);
});

test('Unknown broad names do not prove that a skill works across platforms', () => {
  const result = rank([
    skill('vercel-optimize', 85438, 'vercel-labs/agent-skills'),
    skill('performance', Number.MAX_SAFE_INTEGER),
    skill('react-native-performance', 1),
  ], classify('Optimize slow scrolling in React Native.'));
  assert.deepEqual(result.map(s => s.name), ['react-native-performance']);
});

test('A platform-only prompt can use broad skills without pulling in specialists', () => {
  const result = rank([skill('react-best-practices'), skill('react-testing'), skill('clerk-nextjs-patterns')], classify('Explain React useState.'));
  assert.deepEqual(result.map(s => s.name), ['react-best-practices']);
});
