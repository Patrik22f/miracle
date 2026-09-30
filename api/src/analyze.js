import { randomUUID } from 'node:crypto';
import { catalog } from './catalog.js';
import { signals, capabilities, domains, compatible, label } from './signals.js';
import { promptCriteria, recommendSkills } from './criteria.js';
import { readLibrary } from './skill-library.js';

export function classify(prompt) {
  const tags = signals(prompt, { task: true });
  const intent = tags.includes('debugging') ? 'debug' : tags.includes('performance') ? 'optimize' : tags.includes('design') ? 'design' : tags.includes('testing') ? 'test' : 'general';
  const effort = /\bmigrat\w*\b|\barchitect\w*\b|\brace condition\b|\bdistributed\b/i.test(prompt) ? 'high' : tags.length > 0 || prompt.length > 600 ? 'medium' : 'low';
  const taskDomains = tags.filter(t => domains.includes(t) && t !== 'database');
  const topic = capabilities.find(t => tags.includes(t)) ?? 'best practices';
  // Only controlled topic labels leave this API, never the raw prompt or extracted secrets.
  const queries = [...new Set(taskDomains.slice(0, 2).map(d => `${d.replaceAll('-', ' ')} ${topic}`))];
  if (!queries.length && tags.includes('database')) queries.push(`database ${topic}`);
  if (queries.length === 0 && topic !== 'best practices') queries.push(topic === 'debugging' ? 'systematic debugging' : topic);
  return { intent, effort, tags, queries: queries.slice(0, 3) };
}

export function normalizeSkill(row) {
  if (!row || typeof row !== 'object' || row.isDuplicate === true) return null;
  const source = row.source;
  const name = row.skillId || row.name;
  if (typeof source !== 'string' || !/^[a-zA-Z0-9][\w.-]*\/[a-zA-Z0-9][\w.-]*$/.test(source)) return null;
  if (typeof name !== 'string' || !/^[a-zA-Z0-9][\w.-]{0,119}$/.test(name)) return null;
  const id = `${source}/${name}`;
  const known = catalog.find(s => s.id === id);
  return {
    id, name, source, description: known?.description ?? 'Public skill discovered through skills.sh.',
    tags: known?.tags ?? [],
    installs: Number.isSafeInteger(row.installs) && row.installs >= 0 ? row.installs : null,
    url: `https://skills.sh/${id}`, repositoryUrl: `https://github.com/${source}`, provenance: 'skills.sh',
  };
}

export async function discover(queries, { mode = 'live', timeout = 2500, fetchImpl = fetch } = {}) {
  if (!queries.length) return { candidates: [], source: 'none', warnings: [] };
  if (mode === 'offline') return { candidates: catalog, source: 'catalog', warnings: ['Offline mode: using the bundled public-skill catalog.'] };
  const results = await Promise.allSettled(queries.map(async query => {
    const url = new URL('https://skills.sh/api/search');
    url.searchParams.set('q', query);
    url.searchParams.set('limit', '8');
    const response = await fetchImpl(url, { signal: AbortSignal.timeout(timeout), redirect: 'error', headers: { Accept: 'application/json' } });
    if (!response.ok) throw new Error(`Search HTTP ${response.status}`);
    const body = await response.text();
    if (body.length > 1_000_000) throw new Error('Search response too large');
    const data = JSON.parse(body);
    if (!Array.isArray(data.skills)) throw new Error('Unexpected search response');
    return data.skills.slice(0, 24).map(normalizeSkill).filter(Boolean);
  }));
  const fulfilled = results.filter(r => r.status === 'fulfilled');
  const candidates = [...new Map(fulfilled.flatMap(r => r.value).map(s => [s.id, s])).values()];
  if (fulfilled.length === 0) return { candidates: catalog, source: 'catalog', warnings: ['Public search is unavailable. Showing the bundled catalog instead.'] };
  return { candidates, source: 'skills.sh', warnings: fulfilled.length < results.length ? ['Some skill searches timed out; results may be incomplete.'] : [] };
}

export function rank(candidates, analysis, maxSkills = 3) {
  const requested = new Set(analysis.tags);
  const taskCapabilities = capabilities.filter(t => requested.has(t));
  return [...new Map(candidates.map(skill => [skill.id, skill])).values()].map(skill => {
    const tags = [...new Set([...signals(skill.name), ...skill.tags])];
    const matches = tags.filter(t => requested.has(t));
    const matchedCapabilities = matches.filter(t => capabilities.includes(t));
    const matchedDomains = matches.filter(t => domains.includes(t));
    const candidateCapabilities = tags.filter(t => capabilities.includes(t));
    // A framework name alone does not prove usefulness for a specific task.
    // Prefer fewer recommendations to padding the list with adjacent skills.
    let relevance = matchedCapabilities.length * 3 + matchedDomains.length;
    if (!compatible(tags, requested)) relevance = 0;
    // Unknown names like "optimize" do not establish platform independence.
    // Only locally annotated, general-purpose catalog skills can omit scope.
    if (!tags.some(t => domains.includes(t)) && !skill.tags.length) relevance = 0;
    if (taskCapabilities.length && !matchedCapabilities.length) relevance = 0;
    if (!taskCapabilities.length && candidateCapabilities.length) relevance = 0;
    return { skill, matches, matchedCapabilities, matchedDomains, relevance };
  }).filter(s => s.relevance > 0)
    // Popularity only breaks equal-relevance ties and never creates relevance.
    .sort((a, b) => b.relevance - a.relevance || (b.skill.installs ?? 0) - (a.skill.installs ?? 0) || a.skill.id.localeCompare(b.skill.id))
    .slice(0, maxSkills).map(({ skill, matches, matchedCapabilities, matchedDomains }) => ({
      id: skill.id, name: skill.name, source: skill.source,
      description: skill.description, url: skill.url, repositoryUrl: skill.repositoryUrl,
      installs: skill.installs, provenance: skill.provenance,
      reason: matchedCapabilities.length
        ? `${matchedDomains.length ? `Matches ${matchedDomains.slice(0, 2).map(label).join(' and ')}; focuses` : 'Focuses'} on ${matchedCapabilities.map(label).join(' and ')}.`
        : `Matches the task's ${matchedDomains.map(label).join(' and ')} context.`,
      confidence: Math.min(0.95, 0.45 + matches.length * 0.12),
      security: 'not-audited',
    }));
}

export async function analyze(request, options = {}) {
  const start = performance.now();
  const analysis = classify(request.prompt);
  if (['hybrid', 'installed'].includes(options.mode)) {
    const library = options.library ?? await readLibrary();
    const task = promptCriteria(request.prompt);
    const queries = task.abstain || request.maxSkills === 0 ? [] : task.scopes.slice(0, 2).map(scope => `${scope.replaceAll('-', ' ')} ${task.purposes[0] ?? 'best practices'}`);
    const discovery = options.mode === 'hybrid' && queries.length
      ? await discover(queries, { ...options, mode: 'live' }) : { candidates: [], source: 'none', warnings: [] };
    const imported = options.mode === 'installed' ? library.skills.filter(skill => skill.provenance === 'installed') : library.skills;
    const candidates = [...imported, ...discovery.candidates.filter(skill => !imported.some(local => local.id === skill.id))];
    const skills = recommendSkills(candidates, request.prompt, request.maxSkills ?? 3);
    return {
      schemaVersion: '1.0', requestId: randomUUID(),
      analysis: { intent: analysis.intent, tags: [...new Set([...task.scopes, ...task.purposes])], queries: options.mode === 'hybrid' ? queries : [] },
      effort: { level: analysis.effort, reason: analysis.effort === 'high' ? 'The prompt suggests cross-cutting or complex work.' : 'Effort reflects task complexity, independently of skill fit.' },
      model: { profile: analysis.effort === 'high' ? 'capable' : analysis.effort === 'low' ? 'fast' : 'balanced', reason: 'Choose an available model in your AI app.' },
      skills,
      meta: { source: options.mode === 'hybrid' ? 'hybrid' : 'installed', ranking: 'criteria-v2', importedCount: imported.length,
        durationMs: Math.round(performance.now() - start), warnings: [...library.warnings, ...discovery.warnings] },
    };
  }
  const discovery = await discover(analysis.queries, options);
  return {
    schemaVersion: '1.0', requestId: randomUUID(),
    analysis: { intent: analysis.intent, tags: analysis.tags, queries: analysis.queries },
    effort: { level: analysis.effort, reason: analysis.effort === 'high' ? 'The prompt suggests cross-cutting or complex work.' : analysis.effort === 'medium' ? 'This task benefits from investigation and verification.' : 'A short, direct response should be enough.' },
    model: { profile: analysis.effort === 'high' ? 'capable' : analysis.effort === 'low' ? 'fast' : 'balanced', reason: 'Advisory capability profile; choose an available model in your AI app.' },
    skills: rank(discovery.candidates, analysis, request.maxSkills ?? 3),
    meta: { source: discovery.source, ranking: 'heuristic-v1', durationMs: Math.round(performance.now() - start), warnings: discovery.warnings },
  };
}
