import { randomUUID } from 'node:crypto';
import { catalog } from './catalog.js';

const rules = [
  ['nextjs', /\bnext(?:\.?js)?\b/i], ['react', /\breact\b|\bnext\.?js\b/i],
  ['swift', /\bswift(?:ui)?\b|\bappkit\b|\bmacos\b/i],
  ['postgres', /\bpostgres(?:ql)?\b|\bsupabase\b/i],
  ['database', /\bdatabase\b|\bsql\b|\bpostgres(?:ql)?\b|\bsupabase\b/i],
  ['stripe', /\bstripe\b/i], ['python', /\bpython\b/i],
  ['performance', /\bslow\b|\blag(?:gy)?\b|\bperformance\b|\boptimi[sz]e\b|\brendering\b/i],
  ['debugging', /\bdebug\b|\bbug\b|\bcrash\b|\bbroken\b|\bfix\b|\bwhy\b|\bfail(?:s|ing|ure)?\b/i],
  ['testing', /\btests?\b|\btesting\b|\btdd\b/i],
  ['accessibility', /\baccessib\w*\b|\bvoiceover\b|\bwcag\b/i],
  ['design', /\bdesign\b|\bui\b|\blayout\b|\blanding page\b/i],
  ['frontend', /\breact\b|\bnext\.?js\b|\bcss\b|\bhtml\b|\bfrontend\b|\bweb\b|\blanding page\b/i],
];
const stop = new Set(['the', 'and', 'for', 'with', 'this', 'that', 'from', 'best', 'practices', 'skills', 'skill', 'vercel', 'labs', 'agent']);
const words = s => s.toLowerCase().replaceAll('next.js', 'nextjs').split(/[^a-z0-9]+/).filter(x => x.length > 2 && !stop.has(x));

export function classify(prompt) {
  const tags = rules.filter(([, regex]) => regex.test(prompt)).map(([tag]) => tag);
  const intent = tags.includes('debugging') ? 'debug' : tags.includes('performance') ? 'optimize' : tags.includes('design') ? 'design' : tags.includes('testing') ? 'test' : 'general';
  const effort = /\bmigrat\w*\b|\barchitect\w*\b|\brace condition\b|\bdistributed\b/i.test(prompt) ? 'high' : tags.length > 0 || prompt.length > 600 ? 'medium' : 'low';
  const domains = tags.filter(t => ['react', 'nextjs', 'swift', 'postgres', 'stripe', 'python', 'frontend'].includes(t));
  const topic = tags.includes('performance') ? 'performance' : tags.includes('accessibility') ? 'accessibility' : tags.includes('design') ? 'design' : tags.includes('testing') ? 'testing' : tags.includes('debugging') ? 'debugging' : 'best practices';
  // Only controlled topic labels leave this API, never the raw prompt or extracted secrets.
  const queries = [...new Set(domains.slice(0, 2).map(d => `${d} ${topic}`))];
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
  return candidates.map(skill => {
    const tokens = new Set([...words(`${skill.name} ${skill.source}`), ...skill.tags]);
    const matches = [...requested].filter(t => tokens.has(t));
    // Popularity breaks ties only; it must never create relevance.
    let relevance = matches.length;
    const specialty = ['react', 'nextjs', 'swift', 'postgres', 'stripe', 'python'];
    const candidateDomains = specialty.filter(t => tokens.has(t));
    if (candidateDomains.length && !candidateDomains.some(t => requested.has(t))) relevance = 0;
    const capabilities = skill.tags.filter(t => ['performance', 'debugging', 'testing', 'design', 'accessibility'].includes(t));
    if (capabilities.length && !capabilities.some(t => requested.has(t))) relevance = 0;
    if (/react-native/.test(skill.name) && requested.has('nextjs')) relevance = 0;
    if (/frontend|react|nextjs/.test(skill.name) && requested.has('swift') && !requested.has('frontend')) relevance = 0;
    return { skill, matches, relevance, score: relevance + Math.log10(1 + (skill.installs ?? 0)) / 100 };
  }).filter(s => s.relevance > 0)
    .sort((a, b) => b.score - a.score || a.skill.id.localeCompare(b.skill.id))
    .slice(0, maxSkills).map(({ skill, matches, relevance }) => ({
      id: skill.id, name: skill.name, source: skill.source,
      description: skill.description, url: skill.url, repositoryUrl: skill.repositoryUrl,
      installs: skill.installs, provenance: skill.provenance,
      reason: `Matches the task's ${matches.join(', ')} needs.`,
      confidence: Math.min(0.95, 0.45 + relevance * 0.12),
      security: 'not-audited',
    }));
}

export async function analyze(request, options = {}) {
  const start = performance.now();
  const analysis = classify(request.prompt);
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
