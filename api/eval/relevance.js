import { catalog } from '../src/catalog.js';
import { classify, normalizeSkill, rank } from '../src/analyze.js';

// These are records seen in the live Next.js performance search.
// The rest are deliberately synthetic skills: controlled positive/negative
// examples, not a claim that these packages exist in the public directory.
const liveRows = [
  ['giuseppe-trisciuoglio/developer-kit', 'nextjs-performance', 4480],
  ['clerk/skills', 'clerk-nextjs-patterns', 48019],
  ['expo/skills', 'expo-dev-client', 62968],
  ['vercel-labs/agent-skills', 'vercel-optimize', 85438],
];
const syntheticNames = [
  'react-testing-library', 'python-debugging', 'postgres-performance',
  'react-accessibility', 'swiftui-accessibility', 'react-native-performance',
  'nextjs-authentication', 'react-best-practices', 'python-performance',
  'swiftui-performance', 'vue-performance', 'angular-performance',
  'nextjs-deployment', 'nextjs-seo', 'react-native-testing',
];
export const candidates = [
  ...catalog,
  ...liveRows.map(([source, skillId, installs]) => normalizeSkill({ source, skillId, installs })),
  ...syntheticNames.map(skillId => normalizeSkill({ source: 'evaluation/fixtures', skillId, installs: 100 })),
];

export const cases = [
  {
    id: 'nextjs-performance',
    prompt: 'Optimize this Next.js page. It is slow when rendering 500 products.',
    required: ['vercel-react-best-practices', 'nextjs-performance'],
    allowed: ['vercel-react-best-practices', 'nextjs-performance'],
  },
  {
    id: 'nextjs-authentication',
    prompt: 'Add Clerk authentication and login to my Next.js app.',
    required: ['clerk-nextjs-patterns'],
    allowed: ['clerk-nextjs-patterns', 'nextjs-authentication'],
  },
  {
    id: 'react-tests',
    prompt: 'Write unit tests for this React form using Testing Library.',
    required: ['react-testing-library'],
    allowed: ['react-testing-library', 'test-driven-development', 'systematic-debugging'],
  },
  {
    id: 'python-debugging',
    prompt: 'Debug why my Python CSV parser crashes on empty rows.',
    required: ['python-debugging'],
    allowed: ['python-debugging', 'systematic-debugging'],
  },
  {
    id: 'postgres-performance',
    prompt: 'Optimize this slow Postgres SQL query that joins orders and customers.',
    required: ['supabase-postgres-best-practices'],
    allowed: ['supabase-postgres-best-practices', 'postgres-performance'],
  },
  {
    id: 'web-design',
    prompt: 'Design a landing page for a coffee shop with a clear menu and booking section.',
    required: ['frontend-design'],
    allowed: ['frontend-design', 'web-design-guidelines'],
  },
  {
    id: 'react-accessibility',
    prompt: 'Improve keyboard accessibility in this React dialog to meet WCAG.',
    required: ['react-accessibility'],
    allowed: ['react-accessibility', 'web-design-guidelines'],
  },
  {
    id: 'swiftui-accessibility',
    prompt: 'Make this SwiftUI settings screen accessible with VoiceOver.',
    required: ['swiftui-accessibility'],
    allowed: ['swiftui-accessibility'],
  },
  {
    id: 'react-native-performance',
    prompt: 'Fix slow scrolling in my React Native FlatList on Android.',
    required: ['react-native-performance'],
    allowed: ['react-native-performance', 'systematic-debugging'],
  },
  {
    id: 'no-skill-needed',
    prompt: 'Say hello in Czech.',
    required: [],
    allowed: [],
  },
];

export function assess(testCase, skills) {
  const names = skills.map(skill => skill.name);
  return {
    missing: testCase.required.filter(name => !names.includes(name)),
    unexpected: names.filter(name => !testCase.allowed.includes(name)),
  };
}

export function evaluate() {
  return cases.map(testCase => {
    const skills = rank(candidates, classify(testCase.prompt));
    const { missing, unexpected } = assess(testCase, skills);
    return { id: testCase.id, passed: !missing.length && !unexpected.length, skills: skills.map(s => s.name), missing, unexpected };
  });
}
