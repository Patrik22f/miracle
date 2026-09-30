import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { constants } from 'node:fs';
import { lstat, open, opendir, realpath } from 'node:fs/promises';
import path from 'node:path';
import { createHash } from 'node:crypto';

const exec = promisify(execFile);
const MAX_FILES = 3000;
const MAX_CONTEXT = 48000;
const extensions = new Set(['.swift', '.js', '.mjs', '.cjs', '.ts', '.tsx', '.jsx', '.py', '.rs', '.go', '.java', '.kt', '.c', '.h', '.cpp', '.cs', '.rb', '.php', '.vue', '.svelte', '.md', '.json', '.toml', '.yaml', '.yml', '.html', '.css', '.sql', '.sh']);
const excluded = /(^|\/)(\.[^/]+|node_modules|vendor|build|dist|coverage|DerivedData|Pods|logs|fixtures|__snapshots__)(\/|$)|(?:^|\/)[^/]*(?:secret|credential|private[-_]?key|service[-_]?account)[^/]*(?:\/|$)|(?:^|\/)(?:package-lock\.json|pnpm-lock\.yaml|yarn\.lock)|\.(?:min\.[jt]s|test-data\.json)$/i;

export function eligibleFile(name) {
  return typeof name === 'string' && name.length <= 500 && !path.isAbsolute(name)
    && !name.split('/').includes('..') && !/[\x00-\x1f\\]/.test(name)
    && !excluded.test(name) && extensions.has(path.extname(name).toLowerCase());
}

export function redact(text) {
  return text.replace(/-----BEGIN [^-]*PRIVATE KEY-----[\s\S]*?(?:-----END [^-]*PRIVATE KEY-----|$)/g, '[REDACTED PRIVATE KEY]')
    .replace(/\b(?:gsk_|sk-[A-Za-z0-9_-]*|gh[pousr]_|github_pat_)[A-Za-z0-9_-]{16,}\b/g, '[REDACTED TOKEN]')
    .replace(/((?:api[_-]?key|access[_-]?token|authorization|password|secret)\s*["']?\s*[:=]\s*)[^\n,;]+/gi, '$1[REDACTED]')
    .replace(/(https?:\/\/)[^\s/@]+:[^\s/@]+@/g, '$1[REDACTED]@');
}

async function git(root, args) {
  return (await exec('git', ['-C', root, ...args], { timeout: 3000, maxBuffer: 2 * 1024 * 1024, env: { ...process.env, GIT_OPTIONAL_LOCKS: '0' } })).stdout;
}

async function walk(root) {
  const files = [], pending = [''];
  let visited = 0;
  while (pending.length && visited < 10000 && files.length < MAX_FILES) {
    const parent = pending.pop();
    const directory = await opendir(path.join(root, parent));
    for await (const entry of directory) {
      if (++visited > 10000 || files.length >= MAX_FILES) break;
      const name = parent ? `${parent}/${entry.name}` : entry.name;
      if (entry.isSymbolicLink() || excluded.test(name)) continue;
      if (entry.isDirectory() && name.split('/').length < 12) pending.push(name);
      else if (entry.isFile() && eligibleFile(name)) files.push(name);
    }
  }
  return { files, truncated: pending.length > 0 || visited >= 10000 || files.length >= MAX_FILES };
}

// Never follow a file or directory symlink, including links inside the project.
async function safeStat(root, name) {
  const full = path.join(root, name);
  if (await realpath(full) !== full) return null;
  const stat = await lstat(full);
  return stat.isFile() && stat.size <= 256000 ? stat : null;
}

export async function readProject(projectPath, prompt = '') {
  let root;
  try {
    root = await realpath(projectPath);
    if (!(await lstat(root)).isDirectory() || root === path.parse(root).root) throw new Error();
  } catch { throw new Error('Choose an accessible project folder.'); }
  let files, changed = [], head = '', truncated = false;
  try {
    // Explicit file paths stay relative to the chosen folder, even in a monorepo.
    files = (await git(root, ['ls-files', '-z', '--cached', '--others', '--exclude-standard', '--', '.'])).split('\0').filter(eligibleFile);
    changed = (await git(root, ['ls-files', '-z', '--modified', '--others', '--exclude-standard', '--', '.'])).split('\0').filter(eligibleFile);
    changed.push(...(await git(root, ['diff', '--cached', '--name-only', '-z', '--relative', '--', '.']).catch(() => '')).split('\0').filter(eligibleFile));
    head = (await git(root, ['rev-parse', 'HEAD']).catch(() => '')).trim();
    truncated = files.length > MAX_FILES;
  } catch (error) {
    // A failed Git read must not fall back to walking ignored/private files.
    if (!/not a git repository/i.test(error.stderr ?? '')) throw error;
    const result = await walk(root); files = result.files; truncated = result.truncated;
  }
  files = [...new Set(files)].sort().slice(0, MAX_FILES);
  const changedSet = new Set(changed);
  const words = prompt.toLowerCase().match(/[a-z][a-z0-9_-]{3,}/g) ?? [];
  const score = name => (changedSet.has(name) ? 50 : 0)
    + (/^(README[^/]*|package\.json|Package\.swift|Cargo\.toml|pyproject\.toml)$/i.test(path.basename(name)) ? 80 : 0)
    + words.filter(word => name.toLowerCase().includes(word)).length * 12
    + (/\/(src|Sources|app)\//.test(`/${name}`) ? 10 : 0);
  const stats = [];
  // Bounded concurrency avoids thousands of outstanding filesystem reads.
  for (let start = 0; start < files.length; start += 32) {
    await Promise.all(files.slice(start, start + 32).map(async name => {
      const stat = await safeStat(root, name).catch(() => null);
      if (stat) stats.push({ name, size: stat.size, modified: stat.mtimeMs });
    }));
  }
  stats.sort((a, b) => a.name.localeCompare(b.name));
  const selected = [...stats].sort((a, b) => score(b.name) - score(a.name) || a.name.localeCompare(b.name));
  const excerpts = [];
  let budget = MAX_CONTEXT;
  for (const item of selected) {
    if (excerpts.length >= 18 || budget < 300) break;
    let handle;
    try {
      if (!await safeStat(root, item.name)) continue;
      handle = await open(path.join(root, item.name), constants.O_RDONLY | constants.O_NOFOLLOW);
      const buffer = Buffer.alloc(Math.min(item.size, 3600, budget));
      const { bytesRead } = await handle.read(buffer, 0, buffer.length, 0);
      const content = buffer.subarray(0, bytesRead).toString('utf8');
      if (content.includes('\0')) continue;
      const text = redact(content);
      excerpts.push({ path: item.name, content: text, truncated: bytesRead < item.size });
      budget -= buffer.length;
    } catch { /* A save/delete during scanning is picked up on the next refresh. */ }
    finally { await handle?.close(); }
  }
  const revision = createHash('sha256').update(JSON.stringify({ root, head, stats, excerpts })).digest('hex');
  const tree = stats.slice(0, 1000).map(item => item.name);
  return {
    root, name: path.basename(root), revision, scannedAt: new Date().toISOString(),
    fileCount: stats.length, sampledFileCount: excerpts.length,
    partial: truncated || excerpts.length < stats.length || excerpts.some(item => item.truncated),
    tree, changedFiles: changed.filter(name => tree.includes(name)).slice(0, 80), excerpts,
  };
}
