import { createHash } from 'node:crypto';
import { skillCriteria, promptCriteria, evaluateSkill } from './criteria.js';
import { resolveTask } from './task-context.js';
import { matchesSkillFilters } from './skill-filters.js';

export const knowledgeVersion = 'knowledge-v1';
const compilerRevision = 3;
export const knowledgeThreshold = 70;
export const knowledgeCriteria = [
  ['purpose', 'Task purpose', 18], ['scope', 'Framework and platform', 15],
  ['action', 'Requested operation', 10], ['artifact', 'Output artifact', 7],
  ['trigger', 'Description evidence', 10], ['procedure', 'Instruction evidence', 12],
  ['prerequisites', 'Workflow prerequisites', 5], ['exclusions', 'Negative constraints', 5],
  ['agent', 'Agent compatibility', 5], ['availability', 'Instruction availability', 5],
  ['freshness', 'Snapshot freshness', 3], ['specificity', 'Specialist fit', 5],
].map(([id, label, maximum]) => ({ id, label, maximum }));

const hash = text => createHash('sha256').update(text).digest('hex');
const unique = items => [...new Set(items)];
const words = text => unique(text.toLowerCase().match(/[a-z][a-z0-9-]{2,}/g) ?? []);
const actions = [
  ['create', /\b(?:creat\w*|writ\w*|build\w*|generat\w*|implement\w*)\b/i],
  ['edit', /\b(?:edit\w*|modif\w*|refactor\w*|updat\w*|fix\w*|replac\w*)\b/i],
  ['review', /\b(?:review\w*|audit\w*|inspect\w*|analy[sz]\w*|diagnos\w*)\b/i],
  ['read', /\b(?:read\w*|extract\w*|summari[sz]\w*)\b/i],
  ['optimize', /\b(?:optimi[sz]\w*|performance|slow)\b/i],
];
const operation = text => actions.filter(([, re]) => re.test(text)).map(([name]) => name);
const artifacts = new Set(['pdf', 'documents', 'spreadsheets', 'presentations']);

export { normalizeTask } from './task-context.js';

function bodyLines(content) {
  const lines = content.replaceAll('\r\n', '\n').split('\n');
  let frontmatter = lines[0] === '---', fence = false;
  return lines.flatMap((text, index) => {
    if (frontmatter) { if (index && text === '---') frontmatter = false; return []; }
    if (/^\s*(```|~~~)/.test(text)) { fence = !fence; return []; }
    if (fence || !text.trim()) return [];
    const kind = /\b(?:do not use|don't use|not for|never use|avoid using)\b/i.test(text) ? 'exclusion'
      : /\b(?:requires?|prerequisites?|only when|must have)\b/i.test(text) ? 'prerequisite'
        : /\b(?:use when|when to use|triggers?)\b/i.test(text) ? 'trigger' : 'instruction';
    return [{ line: index + 1, kind, text: text.trim().slice(0, 600) }];
  });
}

// Compilation consumes content once per snapshot. Remote instructions are data;
// they cannot define scoring weights, execute commands, or override host policy.
export function compileSkill(skill) {
  const content = typeof skill.content === 'string' ? skill.content : '';
  const digest = hash(content);
  const lines = bodyLines(content);
  const metadata = content.match(/^---\r?\n([\s\S]*?)\r?\n---/)?.[1] ?? '';
  const references = unique([...content.matchAll(/\]\(((?:\.\/)?(?:references|scripts|assets)\/[^\s)#]+)(?:#[^\s)]*)?\)/g)].map(m => m[1].replace(/^\.\//, '')));
  const instructionLines = lines.filter(row => row.kind !== 'exclusion');
  const profile = skillCriteria(skill);
  const exclusions = [...`${skill.description}\n${content}`.matchAll(/\b(?:do not use|don't use) (?:this skill )?(?:for|when) ([^.;\n]+)/gi)]
    .map(match => promptCriteria(match[1]));
  // An exclusion for an *open Excel workbook* must not exclude every spreadsheet.
  // Preserve the qualifiers and require them, rather than banning whole domains.
  const exclusionScopes = unique(exclusions.filter(rule => !rule.tokens.length).flatMap(rule => rule.scopes));
  return {
    version: knowledgeVersion, compilerRevision, hash: digest,
    valid: Boolean(content.trim()) && (!skill.hash || skill.hash === digest),
    method: 'deterministic-content-profile', profile,
    actions: operation(`${skill.description} ${instructionLines.map(row => row.text).join('\n')}`),
    evidence: lines,
    exclusionScopes,
    exclusions: exclusions.map(({ scopes, tokens }) => ({ scopes, tokens })),
    references,
    missingReferences: skill.files ? references.filter(path => !skill.files.some(file => file.path === path)) : [],
    manualOnly: /^disable-model-invocation:\s*true\s*(?:#.*)?$/mi.test(metadata),
    userInvocable: !/^user-invocable:\s*false\s*(?:#.*)?$/mi.test(metadata),
    // Only unequivocal host extensions constrain portability. Mentioning Codex
    // in ordinary prose does not prove that a skill is incompatible with Claude.
    claudeOnly: /^(?:agent:|hooks:)/m.test(metadata) || /!`[^`]+`|\$\{CLAUDE_SKILL_DIR\}/.test(content),
    codexOnly: /\b(?:functions\.exec|tools\.mcp__codex_app__|mcp__codex_app__\w+)/.test(content),
  };
}

const compiledLibraries = new WeakMap();
export function prepareKnowledge(library) {
  if (compiledLibraries.has(library)) return compiledLibraries.get(library);
  const entries = library.skills.map(skill => {
    const study = skill.study;
    const cached = study?.version === knowledgeVersion && study.compilerRevision === compilerRevision && study.hash === skill.hash
      && study.hash === hash(typeof skill.content === 'string' ? skill.content : '')
      && Array.isArray(study.profile?.scopes) && Array.isArray(study.profile?.purposes)
      && Array.isArray(study.profile?.tokens) && Array.isArray(study.evidence)
      && Array.isArray(study.actions) && Array.isArray(study.references)
      && Array.isArray(study.exclusionScopes) && Array.isArray(study.missingReferences);
    return { skill, knowledge: cached ? study : compileSkill(skill) };
  });
  const postings = new Map();
  const add = (key, entry) => { if (!postings.has(key)) postings.set(key, new Set()); postings.get(key).add(entry); };
  for (const entry of entries) {
    entry.linesByTerm = new Map();
    for (const line of entry.knowledge.evidence.filter(row => row.kind !== 'exclusion')) {
      for (const term of words(line.text)) {
        if (!entry.linesByTerm.has(term)) entry.linesByTerm.set(term, []);
        entry.linesByTerm.get(term).push(line);
      }
    }
    for (const scope of entry.knowledge.profile.scopes) add(`scope:${scope}`, entry);
    for (const purpose of entry.knowledge.profile.purposes) add(`purpose:${purpose}`, entry);
    for (const term of entry.knowledge.profile.tokens) add(`term:${term}`, entry);
    add(`name:${entry.skill.name.toLowerCase()}`, entry);
  }
  const snapshot = { entries, postings };
  compiledLibraries.set(library, snapshot);
  return snapshot;
}

export function recommendKnowledge(library, prompt, { maxSkills = 3, app = '', now = Date.now(), context, resolved, filters } = {}) {
  const plan = resolved ?? resolveTask(prompt, context);
  const task = plan.task;
  const { postings } = prepareKnowledge(library);
  if (!maxSkills || task.abstain) return [];
  const agent = /claude(?:[ -]code)?/i.test(app) ? 'claude-code' : /codex/i.test(app) ? 'codex' : /cursor/i.test(app) ? 'cursor' : 'unknown';
  const keys = [...task.scopes.map(s => `scope:${s}`), ...task.purposes.map(p => `purpose:${p}`),
    ...task.tokens.map(term => `term:${term}`),
    ...(task.positive.toLowerCase().match(/[a-z0-9][a-z0-9_.:-]*/g) ?? []).map(name => `name:${name}`)];
  const candidates = unique(keys.flatMap(key => [...(postings.get(key) ?? [])]));
  const taskActions = operation(task.positive);
  const rows = [];
  for (const { skill, knowledge: k, linesByTerm } of candidates) {
    if (!matchesSkillFilters(skill, filters, k.profile)) continue;
    if (!k.valid || !k.evidence.length) continue;
    const manualInvocation = new RegExp(`(?:^|\\s)/${skill.name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}(?=\\s|$)`, 'i').test(prompt);
    const base = evaluateSkill(skill, manualInvocation ? { ...task, positive: task.positive.replace(`/${skill.name}`, `$${skill.name}`) } : task, k.profile);
    // Explicit invocations never bypass content, agent, or exclusion gates.
    if (!base.eligible || (agent !== 'codex' && k.codexOnly) || (agent !== 'claude-code' && k.claudeOnly)) continue;
    if (k.exclusions.some(rule => rule.scopes.length && rule.scopes.every(scope => task.scopes.includes(scope))
      && rule.tokens.every(token => task.tokens.includes(token))) || k.missingReferences.length) continue;
    if (k.manualOnly && !(agent === 'claude-code' && manualInvocation)) continue;
    if (!k.userInvocable && manualInvocation) continue;
    const evidenceHits = new Map();
    for (const token of task.tokens) for (const line of linesByTerm.get(token) ?? []) {
      if (!evidenceHits.has(line.line)) evidenceHits.set(line.line, { ...line, hits: 0 });
      evidenceHits.get(line.line).hits++;
    }
    const evidence = [...evidenceHits.values()].sort((a, b) => b.hits - a.hits || a.line - b.line).slice(0, 3);
    if (!base.explicit && !evidence.length) continue;
    const instructionTerms = new Set(evidence.flatMap(row => words(row.text)));
    const operationMatch = taskActions.filter(action => k.actions.includes(action));
    const artifactMatch = k.profile.scopes.some(scope => artifacts.has(scope) && task.scopes.includes(scope));
    const age = now - Date.parse(skill.importedAt);
    const values = [
      base.explicit || k.profile.purposes.some(p => task.purposes.includes(p)) ? 18 : 12,
      base.explicit ? 15 : Math.round(base.evidence[1].points * 15 / 25),
      base.explicit || operationMatch.length ? 10 : !taskActions.length ? 5 : 0,
      base.explicit || artifactMatch ? 7 : !task.scopes.some(s => artifacts.has(s)) ? 5 : 0,
      base.explicit ? 10 : Math.min(10, (base.matchedTokens?.length ?? 0) * 2),
      base.explicit ? 12 : Math.min(12, task.tokens.filter(term => instructionTerms.has(term)).length * 3),
      k.missingReferences.length ? 0 : 5,
      5, // The legacy eligibility gate has checked prompt exclusions/prerequisites.
      agent === 'unknown' ? 2 : 5,
      skill.provenance === 'installed' ? 5 : 3,
      Number.isFinite(age) && age >= 0 && age < 7 * 86400000 ? 3 : Number.isFinite(age) && age >= 0 && age < 30 * 86400000 ? 1 : 0,
      k.profile.purposes.length > 0 && k.profile.purposes.length <= 2 ? 5 : 2,
    ];
    const score = values.reduce((a, b) => a + b, 0);
    if (score < knowledgeThreshold) continue;
    rows.push({ skill, k, base, score, values, evidence });
  }
  rows.sort((a, b) => Number(b.base.explicit) - Number(a.base.explicit) || b.values[1] - a.values[1] || b.score - a.score
    || Number(b.skill.provenance === 'installed') - Number(a.skill.provenance === 'installed') || a.skill.id.localeCompare(b.skill.id));
  const selected = [], covered = new Set(), names = new Set();
  for (const row of rows) {
    if (selected.length >= maxSkills) break;
    if (names.has(row.skill.name.toLowerCase()) || (!row.base.explicit && row.base.coverage.every(c => covered.has(c)))) continue;
    names.add(row.skill.name.toLowerCase()); row.base.coverage.forEach(c => covered.add(c)); selected.push(row);
  }
  return selected.map(({ skill, k, base, score, values, evidence }) => ({
    id: skill.id, name: skill.name, source: skill.source, description: skill.description,
    url: skill.url, repositoryUrl: skill.repositoryUrl, installs: skill.installs ?? null,
    provenance: skill.provenance, security: 'not-audited', confidence: score / 100,
    reason: `${base.reason} Instruction evidence: ${evidence.length ? evidence.map(row => `SKILL.md:${row.line}`).join(', ') : 'explicit invocation; read the source before use'}.`,
    evaluation: { score, threshold: knowledgeThreshold, criteria: knowledgeCriteria.map((c, i) => ({ ...c, points: values[i] })) },
    knowledge: { version: k.version, hash: k.hash, method: k.method, evidenceLines: evidence.map(row => row.line),
      referenceCount: k.references.length, missingReferenceCount: k.missingReferences.length },
  }));
}
