import { evaluateKnowledge, knowledgeLibrary, knowledgeCases } from '../api/eval/knowledge.js';
import { prepareKnowledge, recommendKnowledge } from '../api/src/skill-knowledge.js';
import { readLibrary } from '../api/src/skill-library.js';
const results = evaluateKnowledge();
let library = await readLibrary();
if (!library.skills.length) library = knowledgeLibrary;
const start = performance.now(); prepareKnowledge(library); const compilationMs = performance.now() - start;
const durations = [];
for (let i = 0; i < 500; i++) {
  const start = performance.now();
  recommendKnowledge(library, knowledgeCases[i % knowledgeCases.length].prompt, { app: 'Claude Code' });
  durations.push(performance.now() - start);
}
durations.sort((a, b) => a - b);
console.log(JSON.stringify({ corpus: 'Handwritten regression fixtures; not a production accuracy estimate',
  passed: results.filter(r => r.passed).length, total: results.length, failures: results.filter(r => !r.passed),
  performance: { skills: library.skills.length, samples: durations.length, compilationMs, p50Ms: durations[249], p95Ms: durations[474], p99Ms: durations[494], includesNetwork: false, includesHTTP: false, includesHookStartup: false } }, null, 2));
if (results.some(r => !r.passed)) process.exitCode = 1;
