import { createHash, randomUUID } from 'node:crypto';
import { readdir, readFile, stat, mkdir, writeFile, rename, realpath } from 'node:fs/promises';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { pathToFileURL, fileURLToPath } from 'node:url';
import { skillCriteria } from './criteria.js';
import { createSkillsAPI, syncSkillsAPI } from './skills-api.js';
import { compileSkill, knowledgeCriteria, prepareKnowledge } from './skill-knowledge.js';

export const libraryPath = fileURLToPath(new URL('../../.preflight/skills.json', import.meta.url));
export const defaultRoots = [join(homedir(), '.codex', 'skills'), join(homedir(), '.claude', 'skills')];
const maxBytes = 256 * 1024;

// A reviewed public starter library. Only these URLs are fetched during import.
export const publicSources = [
  ['vercel-labs/agent-skills', 'react-best-practices'],
  ['vercel-labs/agent-skills', 'web-design-guidelines'],
  ['obra/superpowers', 'systematic-debugging'],
  ['obra/superpowers', 'test-driven-development'],
  ['supabase/agent-skills', 'supabase-postgres-best-practices'],
  ...['frontend-design', 'pdf', 'docx', 'xlsx', 'pptx'].map(name => ['anthropics/skills', name]),
].map(([source, directory]) => ({ source, url: `https://raw.githubusercontent.com/${source}/main/skills/${directory}/SKILL.md`, directory }));

// Parse just the two top-level scalar fields we need. Never evaluate YAML tags,
// templates, commands, or instructions. Unsupported/malformed metadata is skipped.
export function parseSkill(content) {
  const front = content.replace(/^\uFEFF/, '').replaceAll('\r\n', '\n').match(/^---\n([\s\S]*?)\n---(?:\n|$)/)?.[1];
  if (!front) throw new Error('Missing front matter');
  const field = key => {
    const match = front.match(new RegExp(`^${key}:([^\\n]*)(?:\\n((?:[ \\t]+[^\\n]*(?:\\n|$))*))?`, 'm'));
    if (!match) return '';
    let value = match[1].trim();
    if (/^[>|][-+]?\s*$/.test(value) || !value) value = (match[2] ?? '').split('\n').map(line => line.trim()).join(' ').trim();
    if (value.startsWith('"') && value.endsWith('"')) { try { value = JSON.parse(value); } catch { throw new Error('Invalid quoted metadata'); } }
    else if (value.startsWith("'") && value.endsWith("'")) value = value.slice(1, -1).replaceAll("''", "'");
    if (/^[!&*[{]/.test(value)) throw new Error('Unsupported metadata scalar');
    return value;
  };
  const name = field('name'), description = field('description');
  if (!/^[a-zA-Z0-9][a-zA-Z0-9_.:-]{0,119}$/.test(name) || !description || description.length > 8000) throw new Error('Invalid name or description');
  return { name, description };
}

function record(content, location, source, provenance) {
  const metadata = parseSkill(content);
  const hash = createHash('sha256').update(content).digest('hex');
  const id = provenance === 'installed' ? `installed/${metadata.name}/${createHash('sha256').update(location).digest('hex').slice(0, 12)}` : `${source}/${metadata.name}`;
  return {
    ...metadata, id, source, provenance, content, hash, importedAt: new Date().toISOString(), installs: null,
    url: location, repositoryUrl: provenance === 'installed' ? new URL('.', location).href : `https://github.com/${source}`,
  };
}

async function boundedResponse(response) {
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  const chunks = []; let size = 0;
  for await (const chunk of response.body) {
    size += chunk.length;
    if (size > maxBytes) throw new Error('SKILL.md exceeds 256 KiB');
    chunks.push(chunk);
  }
  return Buffer.concat(chunks).toString('utf8');
}

export async function importSkills({ roots = defaultRoots, includePublic = true, fetchImpl = fetch, previous = null,
  publicProvider = process.env.VERCEL_OIDC_TOKEN ? 'skills-api' : 'starter', discover = false, api } = {}) {
  const skills = [], warnings = [], seen = new Set();
  let scanned = 0, duplicates = 0;
  async function walk(directory, depth = 0) {
    if (depth > 8 || scanned >= 2000) { warnings.push(`Import limit reached at ${directory}.`); return; }
    const canonical = await realpath(directory);
    if (seen.has(canonical)) return;
    seen.add(canonical);
    const entries = (await readdir(canonical, { withFileTypes: true })).sort((a, b) => a.name.localeCompare(b.name));
    for (const entry of entries) {
      const path = join(canonical, entry.name);
      if (entry.isFile() && entry.name === 'SKILL.md') {
        scanned++;
        try {
          if ((await stat(path)).size > maxBytes) throw new Error('SKILL.md exceeds 256 KiB');
          const content = await readFile(path, 'utf8');
          skills.push(record(content, pathToFileURL(path).href, 'Installed on this Mac', 'installed'));
        } catch (error) { warnings.push(`Skipped ${path}: ${error.message}.`); }
      } else if (entry.isDirectory() && !['.git', 'node_modules', 'references', 'assets', 'scripts', 'build'].includes(entry.name)) {
        try { await walk(path, depth + 1); } catch (error) { warnings.push(`Skipped ${path}: ${error.code ?? 'unreadable'}.`); }
      }
      // Do not follow nested symlinks outside a configured root.
    }
  }
  const resolvedRoots = unique(roots.map(root => resolve(root)));
  for (const root of resolvedRoots) {
    try { await walk(root); } catch (error) { warnings.push(`Cannot import ${root}: ${error.code ?? 'unreadable'}.`); }
  }
  if (includePublic && publicProvider === 'skills-api') {
    const result = await syncSkillsAPI({ api: api ?? createSkillsAPI({ fetchImpl }), discover, previous, makeRecord: record });
    skills.push(...result.skills); warnings.push(...result.warnings);
  } else if (includePublic) {
    const results = await Promise.allSettled(publicSources.map(async source => {
      const response = await fetchImpl(source.url, { signal: AbortSignal.timeout(6000), redirect: 'error' });
      const content = await boundedResponse(response);
      return { ...record(content, `https://github.com/${source.source}/blob/main/skills/${source.directory}/SKILL.md`, source.source, 'public-import'), importUrl: source.url };
    }));
    results.forEach((result, i) => {
      if (result.status === 'fulfilled') skills.push(result.value);
      else {
        const cached = previous?.skills.find(skill => skill.importUrl === publicSources[i].url);
        if (cached) skills.push(cached);
        warnings.push(`Public import failed for ${publicSources[i].source}/${publicSources[i].directory}${cached ? '; kept the previous snapshot' : ''}.`);
      }
    });
  }
  // Identical nested plugin copies collapse; distinct definitions with the same
  // name remain inspectable. Recommendation selection still deduplicates names.
  const deduped = new Map();
  for (const skill of skills) {
    const key = `${skill.provenance}:${skill.name}:${skill.hash}`;
    if (deduped.has(key)) duplicates++; else deduped.set(key, skill);
  }
  return { version: 1, importedAt: new Date().toISOString(), roots: resolvedRoots, includePublic, publicProvider, discover, scanned, duplicates,
    skills: [...deduped.values()].map(skill => ({ ...skill, study: compileSkill(skill) }))
      .sort((a, b) => a.name.localeCompare(b.name) || a.id.localeCompare(b.id)), warnings };
}
const unique = xs => [...new Set(xs)];

export async function saveLibrary(library, path = libraryPath) {
  await mkdir(dirname(path), { recursive: true });
  const temporary = `${path}.${randomUUID()}.tmp`;
  await writeFile(temporary, JSON.stringify(library, null, 2), { mode: 0o600 });
  await rename(temporary, path);
}

export async function readLibrary(path = libraryPath) {
  try {
    const library = JSON.parse(await readFile(path, 'utf8'));
    if (library.version !== 1 || !Array.isArray(library.skills) || !Array.isArray(library.roots)) throw new Error('Invalid skill library');
    return library;
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
    return { version: 1, roots: defaultRoots, includePublic: true, skills: [], warnings: ['Import skills from the Skill library to get started.'] };
  }
}

export function librarySummary(library) {
  return {
    importedAt: library.importedAt ?? null, count: library.skills.length,
    installedCount: library.skills.filter(s => s.provenance === 'installed').length,
    publicCount: library.skills.filter(s => s.provenance === 'public-import').length,
    warnings: library.warnings, criteria: knowledgeCriteria,
    skills: library.skills.map(skill => ({
      id: skill.id, name: skill.name, description: skill.description, source: skill.source,
      provenance: skill.provenance, url: skill.url,
      scopes: skillCriteria(skill).scopes, purposes: skillCriteria(skill).purposes,
    })),
  };
}

// One disk snapshot shared by simultaneous requests. Atomic importer replacement
// invalidates it on the next check; a failed refresh preserves the last good state.
export function createLibraryStore(path = libraryPath, { interval = 1000 } = {}) {
  let snapshot, signature, checked = -Infinity, pending;
  return async function current() {
    if (snapshot && performance.now() - checked < interval) return snapshot;
    if (pending) return pending;
    pending = (async () => {
      try {
        const info = await stat(path).catch(error => { if (error.code === 'ENOENT') return null; throw error; });
        const next = info ? `${info.ino}:${info.size}:${info.mtimeMs}:${info.ctimeMs}` : 'absent';
        if (!snapshot || signature !== next) {
          const library = await readLibrary(path);
          prepareKnowledge(library);
          snapshot = library; signature = next;
        }
      } catch (error) {
        if (!snapshot) throw error;
        snapshot = { ...snapshot, warnings: [...new Set([...snapshot.warnings, 'Library refresh failed; using the last valid snapshot.'])] };
      }
      checked = performance.now();
      return snapshot;
    })().finally(() => { pending = null; });
    return pending;
  };
}
