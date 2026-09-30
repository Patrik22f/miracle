import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const request = await readFile(new URL('../contracts/fixtures/analyze-request.json', import.meta.url), 'utf8');
const response = await fetch(`http://127.0.0.1:${process.env.PORT ?? 8787}/analyze`, {
  method: 'POST', headers: { 'Content-Type': 'application/json' }, body: request, signal: AbortSignal.timeout(15000),
});
assert.equal(response.status, 200);
const data = await response.json();
assert.equal(data.schemaVersion, '1.0');
assert.ok(data.skills.some(s => s.name === 'vercel-react-best-practices'));
console.log(JSON.stringify({ source: data.meta.source, skills: data.skills.map(s => s.name), durationMs: data.meta.durationMs }, null, 2));
