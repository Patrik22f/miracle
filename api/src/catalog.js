// Small fallback catalog, not a mirror of public skill contents.
// Descriptions are our summaries. Counts and security audits are not invented.
export const catalog = [
  ['vercel-labs/agent-skills', 'vercel-react-best-practices', 'React and Next.js performance patterns.', ['react', 'nextjs', 'performance', 'frontend']],
  ['vercel-labs/agent-skills', 'web-design-guidelines', 'Review web interfaces for usability and accessibility.', ['frontend', 'design', 'accessibility']],
  ['obra/superpowers', 'systematic-debugging', 'Investigate root causes before changing code.', ['debugging', 'testing']],
  ['obra/superpowers', 'test-driven-development', 'Use a failing test to guide implementation.', ['testing']],
  ['supabase/agent-skills', 'supabase-postgres-best-practices', 'Postgres query and database design guidance.', ['postgres', 'database', 'performance']],
  ['anthropics/skills', 'frontend-design', 'Build considered web interfaces.', ['frontend', 'design']]
].map(([source, name, description, tags]) => ({
  id: `${source}/${name}`, name, source, description, tags, installs: null,
  url: `https://skills.sh/${source}/${name}`,
  repositoryUrl: `https://github.com/${source}`,
  provenance: 'catalog',
}));
