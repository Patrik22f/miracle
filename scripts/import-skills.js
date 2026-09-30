import { importSkills, readLibrary, saveLibrary, defaultRoots } from '../api/src/skill-library.js';

const args = process.argv.slice(2), roots = [];
let includePublic = true;
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--root' && args[i + 1] && !args[i + 1].startsWith('--')) roots.push(args[++i]);
  else if (args[i] === '--local-only') includePublic = false;
  else throw new Error('Usage: npm run skills:import -- [--root /path/to/skills] [--local-only]');
}
const previous = await readLibrary();
const library = await importSkills({ roots: roots.length ? roots : defaultRoots, includePublic, previous });
await saveLibrary(library);
console.log(`Imported ${library.skills.filter(s => s.provenance === 'installed').length} installed skills and ${library.skills.filter(s => s.provenance === 'public-import').length} public skills; collapsed ${library.duplicates} identical copies.`);
for (const warning of library.warnings) console.warn(warning);
