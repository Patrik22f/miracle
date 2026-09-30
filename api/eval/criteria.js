import { recommendSkills } from '../src/criteria.js';

export const fixtureSkill = (name, description, provenance = 'installed') => ({
  id: `${provenance}/${name}`, name, description, provenance, source: 'Evaluation fixture',
  content: 'Non-executable fixture instructions.',
  url: provenance === 'installed' ? `file:///example/skills/${name}/SKILL.md` : `https://example.com/${name}`,
  repositoryUrl: 'https://example.com', installs: null,
});
export const criterionCandidates = [
  fixtureSkill('swift-concurrency', 'Diagnose Swift actor isolation, Sendable and data races.'),
  fixtureSkill('swift-concurrency-expert', 'Review Swift concurrency and actor isolation.'),
  fixtureSkill('swiftui-accessibility-auditor', 'Audit SwiftUI views for accessibility and VoiceOver.'),
  fixtureSkill('uikit-accessibility-auditor', 'Audit UIKit views for accessibility and VoiceOver.'),
  fixtureSkill('swiftui-performance-audit', 'Optimize slow SwiftUI scrolling and rendering performance.'),
  fixtureSkill('swiftui-expert-skill', 'Write and review SwiftUI views.'),
  fixtureSkill('swiftdata-testing', 'Write SwiftData persistence tests.'),
  fixtureSkill('asc-release-flow', 'Prepare an App Store release and submit for review.'),
  fixtureSkill('asc-testflight-orchestration', 'Distribute TestFlight beta builds.'),
  fixtureSkill('axiom-fix-build', 'Fix Xcode build errors.'),
  fixtureSkill('python-performance', 'Optimize slow Python code.'),
  fixtureSkill('clerk-nextjs-authentication', 'Add Clerk authentication to Next.js.'),
  fixtureSkill('react-native-performance', 'Optimize slow React Native FlatList scrolling.', 'public-import'),
  fixtureSkill('vercel-react-best-practices', 'React and Next.js performance optimization.', 'public-import'),
  fixtureSkill('web-design-guidelines', 'Review web design and accessibility.', 'public-import'),
  fixtureSkill('frontend-design', 'Design a web landing page.', 'public-import'),
  fixtureSkill('supabase-postgres-best-practices', 'Optimize slow Postgres database queries.', 'public-import'),
  fixtureSkill('systematic-debugging', 'Debug software bugs and unexpected behavior.', 'public-import'),
  fixtureSkill('xlsx', 'Create and edit Excel spreadsheets.', 'public-import'),
  fixtureSkill('pdf', 'Create or edit PDF files.', 'public-import'),
];

export const criterionCases = [
  { id: 'actor-error', prompt: 'Fix a Swift Sendable actor isolation error.', required: ['swift-concurrency'], allowed: ['swift-concurrency'] },
  { id: 'swiftui-accessibility', prompt: 'Make this SwiftUI screen accessible with VoiceOver.', required: ['swiftui-accessibility-auditor'], allowed: ['swiftui-accessibility-auditor'] },
  { id: 'uikit-accessibility', prompt: 'Audit UIKit accessibility and VoiceOver.', required: ['uikit-accessibility-auditor'], allowed: ['uikit-accessibility-auditor'] },
  { id: 'swiftui-performance', prompt: 'Optimize slow SwiftUI scrolling.', required: ['swiftui-performance-audit'], allowed: ['swiftui-performance-audit'] },
  { id: 'swiftdata-testing', prompt: 'Write unit tests for SwiftData persistence.', required: ['swiftdata-testing'], allowed: ['swiftdata-testing'] },
  { id: 'release', prompt: 'Prepare an App Store release and submit for review.', required: ['asc-release-flow'], allowed: ['asc-release-flow'] },
  { id: 'testflight', prompt: 'Distribute TestFlight beta builds.', required: ['asc-testflight-orchestration'], allowed: ['asc-testflight-orchestration'] },
  { id: 'web-performance', prompt: 'Optimize slow Next.js rendering.', required: ['vercel-react-best-practices'], allowed: ['vercel-react-best-practices'] },
  { id: 'native-performance', prompt: 'Optimize slow React Native FlatList scrolling.', required: ['react-native-performance'], allowed: ['react-native-performance'] },
  { id: 'postgres-performance', prompt: 'Optimize a slow Postgres query.', required: ['supabase-postgres-best-practices'], allowed: ['supabase-postgres-best-practices'] },
  { id: 'spreadsheet', prompt: 'Create an Excel spreadsheet for my budget.', required: ['xlsx'], allowed: ['xlsx'] },
  { id: 'pdf', prompt: 'Create a PDF report.', required: ['pdf'], allowed: ['pdf'] },
  { id: 'greeting', prompt: 'Say hello in Czech.', required: [], allowed: [] },
  { id: 'ordinary-fix', prompt: 'Fix a typo in this birthday invitation.', required: [], allowed: [] },
  { id: 'explicit-skill', prompt: 'Use $swiftui-expert-skill to review this SwiftUI view.', required: ['swiftui-expert-skill'], allowed: ['swiftui-expert-skill'] },
  { id: 'no-skills', prompt: 'Optimize React performance without any skills.', required: [], allowed: [] },
  { id: 'excluded-framework', prompt: 'Optimize slow SwiftUI scrolling, not React performance.', required: ['swiftui-performance-audit'], allowed: ['swiftui-performance-audit'] },
  { id: 'excluded-skill', prompt: 'Optimize SwiftUI performance. Do not use swiftui-performance-audit.', required: [], allowed: [] },
  { id: 'two-platforms', prompt: 'Improve SwiftUI and React accessibility.', required: ['swiftui-accessibility-auditor', 'web-design-guidelines'], allowed: ['swiftui-accessibility-auditor', 'web-design-guidelines'] },
  { id: 'complementary-skills', prompt: 'Improve SwiftUI accessibility and performance.', required: ['swiftui-accessibility-auditor', 'swiftui-performance-audit'], allowed: ['swiftui-accessibility-auditor', 'swiftui-performance-audit'] },
];

export function evaluateCriteria() {
  return criterionCases.map(testCase => {
    const names = recommendSkills(criterionCandidates, testCase.prompt).map(skill => skill.name);
    const missing = testCase.required.filter(name => !names.includes(name));
    const unexpected = names.filter(name => !testCase.allowed.includes(name));
    return { id: testCase.id, passed: !missing.length && !unexpected.length, skills: names, missing, unexpected };
  });
}
