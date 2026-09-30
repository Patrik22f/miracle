import path from 'node:path';
import { createSuggestionService } from '../api/src/prompt-suggestions.js';

try { process.loadEnvFile('.env'); } catch (error) { if (error.code !== 'ENOENT') throw error; }
const projectPath = path.resolve(process.argv[2] || '.');
const start = performance.now();
const suggest = createSuggestionService();
const result = await suggest({ projectPath, prompt: 'Suggest the next useful implementation tasks based on the current code. Avoid work already completed.' });
console.log(JSON.stringify({ status: result.status, durationMs: Math.round(performance.now() - start),
  model: result.model, project: result.project?.name, sampledFiles: result.project?.sampledFileCount,
  titles: result.suggestions.map(item => item.title), message: result.message }, null, 2));
if (result.status !== 'ready' || result.suggestions.length !== 3) process.exitCode = 1;
else {
  const cached = await suggest({ projectPath, prompt: 'Suggest the next useful implementation tasks based on the current code. Avoid work already completed.' });
  console.log(`Cached repeat: ${cached.cached === true ? 'passed' : 'failed'}`);
  if (!cached.cached) process.exitCode = 1;
}
