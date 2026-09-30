import { criterionCandidates, criterionCases } from './criteria.js';
import { recommendKnowledge } from '../src/skill-knowledge.js';

// Deterministic regression corpus, intentionally not advertised as field accuracy.
export const knowledgeLibrary = { warnings: [], skills: criterionCandidates.map(skill => ({ ...skill,
  importedAt: '2026-09-30T00:00:00Z', content: `# Instructions\n${skill.description}\n## Workflow\nReview the relevant source. Verify changes for ${skill.description}`,
})) };
export const knowledgeCases = [
  ...criterionCases,
  { id: 'cz-voiceover', prompt: 'Oprav přístupnost SwiftUI obrazovky s VoiceOver.', required: ['swiftui-accessibility-auditor'], allowed: ['swiftui-accessibility-auditor'] },
  { id: 'cz-performance', prompt: 'Zrychli pomalé SwiftUI scrollování.', required: ['swiftui-performance-audit'], allowed: ['swiftui-performance-audit'] },
  { id: 'cz-no-skills', prompt: 'Optimalizuj React, bez skillů.', required: [], allowed: [] },
  { id: 'cz-negative', prompt: 'Optimalizuj SwiftUI. Nepoužívej swiftui-performance-audit.', required: [], allowed: [] },
  { id: 'unrelated-question', prompt: 'What is the weather tomorrow?', required: [], allowed: [] },
  { id: 'vague-work', prompt: 'Make it enterprise level.', required: [], allowed: [] },
  { id: 'named-provider-required', prompt: 'Add authentication to a Next.js app.', required: [], allowed: [] },
  { id: 'claude-slash', prompt: '/swift-concurrency', required: ['swift-concurrency'], allowed: ['swift-concurrency'] },
];
export function evaluateKnowledge(library = knowledgeLibrary) {
  return knowledgeCases.map(row => {
    const result = recommendKnowledge(library, row.prompt, { app: 'Claude Code', now: Date.parse('2026-09-30T12:00:00Z') });
    const names = result.map(skill => skill.name);
    const missing = row.required.filter(name => !names.includes(name));
    const unexpected = names.filter(name => !row.allowed.includes(name));
    return { id: row.id, passed: !missing.length && !unexpected.length, names, missing, unexpected };
  });
}
