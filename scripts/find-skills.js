#!/usr/bin/env node
import { pathToFileURL } from 'node:url';
import { readLibrary } from '../api/src/skill-library.js';
import { analyze } from '../api/src/analyze.js';
import { validateRequest } from '../api/src/server.js';
import { filterKeys } from '../api/src/skill-filters.js';

export function parseFindArgs(args) {
  const request = { app: 'Codex', maxSkills: 3, filters: {} };
  let json = false;
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === '--json') { json = true; continue; }
    if (!arg.startsWith('--') && request.prompt === undefined) { request.prompt = arg; continue; }
    const key = arg.slice(2);
    if (!arg.startsWith('--') || !['app', 'limit', ...filterKeys].includes(key) || !args[i + 1] || args[i + 1].startsWith('--')) {
      throw new Error('Usage: npm run --silent skills:find -- "task" [--app Codex] [--provenance installed|public-import] [--source owner/repo] [--scope scope] [--purpose purpose] [--q text] [--limit 1–8] [--json]');
    }
    const value = args[++i];
    if (key === 'app') request.app = value;
    else if (key === 'limit') request.maxSkills = Number(value);
    else request.filters[key] = value;
  }
  const error = validateRequest(request);
  if (error) throw new Error(error);
  return { request, json };
}

export function formatMatches(result) {
  const best = result.skills.find(skill => skill.id === result.meta.bestSkillId);
  const lines = best
    ? [`Best match: ${best.name} (${best.evaluation.score}/100)`, `Source: ${best.url}`, best.reason,
      ...result.skills.slice(1).map(skill => `Also relevant: ${skill.name} (${skill.evaluation.score}/100) — ${skill.url}`)]
    : ['No eligible skill matches this task and its filters.'];
  return [...lines, ...result.meta.warnings.map(warning => `Warning: ${warning}`)].join('\n') + '\n';
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const { request, json } = parseFindArgs(process.argv.slice(2));
    const result = await analyze(request, { mode: 'knowledge', library: await readLibrary() });
    process.stdout.write(json ? JSON.stringify(result, null, 2) + '\n' : formatMatches(result));
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
