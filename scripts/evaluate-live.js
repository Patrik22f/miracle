import assert from 'node:assert/strict';
import { analyze } from '../api/src/analyze.js';

// Live discovery changes over time. These check the demo's essential behavior,
// not an exact ordering or an exact number of recommendations.
const cases = [
  {
    name: 'Next.js performance',
    prompt: 'Optimize this Next.js page. It is slow when rendering 500 products.',
    useful: /react-best-practices|nextjs-performance|react-performance/,
    unrelated: /clerk|auth|native|expo|deploy/,
  },
  {
    name: 'Clerk authentication',
    prompt: 'Add Clerk authentication and login to my Next.js app.',
    useful: /clerk|auth/,
    unrelated: /performance|optimi[sz]e|native|expo/,
  },
  {
    name: 'React Native performance',
    prompt: 'Optimize slow scrolling in my React Native FlatList on Android.',
    useful: /react-native|expo/,
    unrelated: /nextjs|vercel-react|vercel-optimize|clerk|postgres/,
  },
];

let failures = 0;
for (const scenario of cases) {
  const result = await analyze({ prompt: scenario.prompt }, { timeout: 5000 });
  const names = result.skills.map(s => s.name);
  try {
    assert.equal(result.meta.source, 'skills.sh', 'Live discovery did not succeed');
    assert.ok(names.some(name => scenario.useful.test(name)), 'Expected a useful recommendation');
    assert.ok(!names.some(name => scenario.unrelated.test(name)), 'Unrelated skill was recommended');
    console.log(`PASS ${scenario.name}: ${names.join(', ')} (${result.meta.durationMs} ms)`);
  } catch (error) {
    failures++;
    console.error(`FAIL ${scenario.name}: ${error.message}; source=${result.meta.source}; skills=${names.join(', ') || '(none)'}`);
  }
}
console.log(`\n${cases.length - failures}/${cases.length} live checks passed.`);
if (failures) process.exitCode = 1;
