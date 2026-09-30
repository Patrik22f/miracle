import { skillCriteria } from './criteria.js';

export const filterKeys = ['q', 'provenance', 'source', 'scope', 'purpose'];

export function validateSkillFilters(filters) {
  if (filters === undefined) return null;
  if (!filters || typeof filters !== 'object' || Array.isArray(filters)) return 'filters must be an object.';
  if (Object.keys(filters).some(key => !filterKeys.includes(key))) return 'Unknown skill filter.';
  for (const [key, value] of Object.entries(filters)) {
    if (typeof value !== 'string' || !value.trim() || value.length > 200) return `${key} must contain 1–200 characters.`;
  }
  if (filters.provenance && !['installed', 'public-import', 'skills.sh', 'catalog'].includes(filters.provenance)) return 'Invalid skill provenance.';
  return null;
}

// AND across fields and search terms. Search metadata only; matching text is not
// proof that a skill is eligible for a task. The ranker still checks its content.
export function matchesSkillFilters(skill, filters = {}, profile) {
  if (filters.provenance && skill.provenance !== filters.provenance) return false;
  if (filters.source && skill.source.toLowerCase() !== filters.source.trim().toLowerCase()) return false;
  const criteria = profile ?? (skill.scopes ? skill : skillCriteria(skill));
  if (filters.scope && !criteria.scopes.includes(filters.scope.trim().toLowerCase())) return false;
  if (filters.purpose && !criteria.purposes.includes(filters.purpose.trim().toLowerCase())) return false;
  const searchable = `${skill.name} ${skill.description} ${skill.source} ${criteria.scopes.join(' ')} ${criteria.purposes.join(' ')}`.toLowerCase();
  return (filters.q?.toLowerCase().trim().split(/\s+/) ?? []).every(term => searchable.includes(term));
}
