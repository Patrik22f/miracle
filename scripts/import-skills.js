import { importSkills, readLibrary, saveLibrary, defaultRoots } from '../api/src/skill-library.js';

try { process.loadEnvFile('.env'); } catch (error) { if (error.code !== 'ENOENT') throw error; }
const args = process.argv.slice(2), roots = [];
let includePublic = true, publicProvider, discover = false, searchOwner;
const searchQueries = [];
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--root' && args[i + 1] && !args[i + 1].startsWith('--')) roots.push(args[++i]);
  else if (args[i] === '--local-only') includePublic = false;
  else if (args[i] === '--api') publicProvider = 'skills-api';
  else if (args[i] === '--discover') { publicProvider = 'skills-api'; discover = true; }
  else if (args[i] === '--query' && args[i + 1] && !args[i + 1].startsWith('--')) { publicProvider = 'skills-api'; searchQueries.push(args[++i]); }
  else if (args[i] === '--owner' && args[i + 1] && !args[i + 1].startsWith('--')) searchOwner = args[++i];
  else throw new Error('Usage: npm run skills:import -- [--root /path/to/skills] [--local-only | --api | --discover | --query "topic" [--owner owner]]');
}
if (searchOwner && !searchQueries.length) throw new Error('--owner requires --query.');
if (!includePublic && publicProvider) throw new Error('--local-only cannot be combined with public discovery.');
if (publicProvider === 'skills-api' && !process.env.VERCEL_OIDC_TOKEN) throw new Error('Official Skills API requires VERCEL_OIDC_TOKEN. Local imports remain available without it.');
const previous = await readLibrary();
const library = await importSkills({ roots: roots.length ? roots : defaultRoots, includePublic, publicProvider, discover, searchQueries, searchOwner, previous });
await saveLibrary(library);
console.log(`Imported ${library.skills.filter(s => s.provenance === 'installed').length} installed skills and ${library.skills.filter(s => s.provenance === 'public-import').length} public skills; collapsed ${library.duplicates} identical copies.`);
for (const warning of library.warnings) console.warn(warning);
