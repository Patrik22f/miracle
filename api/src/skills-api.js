// Official skills.sh v1 API. Credentials and prompts never enter the snapshot.
// Refresh is deliberately separate from prompt analysis.
const origin = 'https://skills.sh';
const sourcePattern = /^[a-zA-Z0-9][\w.-]*\/[a-zA-Z0-9][\w.-]*$/;
const segmentPattern = /^[a-zA-Z0-9][\w.-]{0,119}$/;
const allowedSources = new Set(['vercel-labs/agent-skills', 'obra/superpowers', 'anthropics/skills', 'supabase/agent-skills']);
export const apiSeeds = [
  'vercel-labs/agent-skills/vercel-react-best-practices', 'vercel-labs/agent-skills/web-design-guidelines',
  'obra/superpowers/systematic-debugging', 'obra/superpowers/test-driven-development',
  'supabase/agent-skills/supabase-postgres-best-practices',
  ...['frontend-design', 'pdf', 'docx', 'xlsx', 'pptx'].map(name => `anthropics/skills/${name}`),
];
const validID = id => typeof id === 'string' && id.split('/').length === 3 && id.split('/').every(part => segmentPattern.test(part));

async function readJSON(response, limit = 2 * 1024 * 1024) {
  if (!response.ok) throw new Error(`Skills API HTTP ${response.status}`);
  let length = 0; const chunks = [];
  for await (const chunk of response.body) {
    length += chunk.length;
    if (length > limit) throw new Error('Skills API response exceeds 2 MiB');
    chunks.push(chunk);
  }
  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}

export function createSkillsAPI({ tokenProvider = () => process.env.VERCEL_OIDC_TOKEN, fetchImpl = fetch, timeout = 6000 } = {}) {
  async function request(path) {
    const token = await tokenProvider();
    if (typeof token !== 'string' || !token.trim()) throw new Error('Skills API requires a Vercel OIDC token');
    return readJSON(await fetchImpl(`${origin}/api/v1/skills${path}`, {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
      redirect: 'error', signal: AbortSignal.timeout(timeout),
    }));
  }
  return {
    async curatedIDs() {
      const response = await request('/curated');
      if (!Array.isArray(response.data)) throw new Error('Invalid curated response');
      // Discovery is bounded and source-allowlisted, never user-prompt driven.
      return [...new Set(response.data.flatMap(owner => Array.isArray(owner.skills) ? owner.skills : [])
        .filter(row => row && !row.isDuplicate && validID(row.id) && allowedSources.has(row.source)
          && row.id.startsWith(`${row.source}/`)).map(row => row.id))].slice(0, 30);
    },
    async detail(id) {
      if (!validID(id)) throw new Error('Invalid skill ID');
      const data = await request(`/${id}`);
      const source = id.split('/').slice(0, 2).join('/');
      if (data.id !== id || data.source !== source || !sourcePattern.test(data.source) || !Array.isArray(data.files) || data.files.length > 256) throw new Error('Invalid skill detail');
      const paths = new Set();
      for (const file of data.files) {
        if (typeof file.path !== 'string' || typeof file.contents !== 'string' || file.path.length > 500
          || /[\\\x00-\x1f]/.test(file.path) || file.path.startsWith('/')
          || file.path.split('/').some(part => !part || part === '..' || part === '.') || paths.has(file.path)) throw new Error('Invalid skill file path');
        paths.add(file.path);
      }
      const content = data.files.find(file => file.path === 'SKILL.md')?.contents;
      if (!content || Buffer.byteLength(content) > 256 * 1024) throw new Error('Missing or oversized SKILL.md');
      return { id, source, content, files: data.files.map(file => ({ path: file.path, contents: file.contents })),
        upstreamHash: typeof data.hash === 'string' ? data.hash : null,
        installs: Number.isSafeInteger(data.installs) && data.installs >= 0 ? data.installs : null };
    },
  };
}

export async function syncSkillsAPI({ api = createSkillsAPI(), discover = false, previous, makeRecord } = {}) {
  let ids = apiSeeds; const warnings = [];
  if (discover) {
    try { ids = [...new Set([...apiSeeds, ...await api.curatedIDs()])].slice(0, 30); }
    catch {
      ids = [...new Set([...apiSeeds, ...(previous?.skills ?? []).map(skill => skill.apiId)
        .filter(id => validID(id) && allowedSources.has(id.split('/').slice(0, 2).join('/')))])].slice(0, 30);
      warnings.push('Curated Skills API discovery failed; retaining the previously configured candidate set.');
    }
  }
  const skills = []; let cursor = 0;
  const started = performance.now();
  // Four bounded workers, one attempt per skill. A failed/expired token is not
  // replaced by an unauthenticated endpoint; previously acquired content survives.
  await Promise.all(Array.from({ length: 4 }, async () => {
    while (cursor < ids.length) {
      const id = ids[cursor++];
      try {
        if (performance.now() - started >= 12000) throw new Error('Refresh deadline');
        const detail = await api.detail(id);
        const record = makeRecord(detail.content, `https://skills.sh/${id}`, detail.source, 'public-import');
        skills.push({ ...record, id, apiId: id, files: detail.files, upstreamHash: detail.upstreamHash, installs: detail.installs });
      } catch {
        const cached = previous?.skills.find(skill => skill.apiId === id);
        if (cached) skills.push(cached);
        warnings.push(`Skills API could not refresh ${id}${cached ? '; kept previous snapshot' : ''}.`);
      }
    }
  }));
  return { skills, warnings };
}
