import { evaluate } from '../api/eval/relevance.js';
import { evaluateCriteria } from '../api/eval/criteria.js';

const results = [...evaluate(), ...evaluateCriteria().map(result => ({ ...result, id: `criteria/${result.id}` }))];
for (const result of results) {
  console.log(`${result.passed ? 'PASS' : 'FAIL'} ${result.id}: ${result.skills.join(', ') || '(no skills)'}`);
  if (result.missing.length) console.log(`  Missing: ${result.missing.join(', ')}`);
  if (result.unexpected.length) console.log(`  Unrelated: ${result.unexpected.join(', ')}`);
}
console.log(`\n${results.filter(r => r.passed).length}/${results.length} relevance cases passed (controlled fixtures, no network).`);
if (results.some(r => !r.passed)) process.exitCode = 1;
