// Controlled vocabulary shared by task classification and skill-name matching.
// Repository/owner names are deliberately not evidence of a skill's purpose.
const rules = [
  ['nextjs', /\bnext(?:\.?js| js)\b/i],
  ['react', /\breact\b/i],
  ['react-native', /\breact native\b|\bexpo\b|\bflatlist\b/i],
  ['vue', /\bvue(?:\.?js)?\b|\bnuxt\b/i],
  ['angular', /\bangular\b/i],
  ['swift', /\bswift(?:ui)?\b|\bappkit\b|\bmacos\b/i],
  ['postgres', /\bpostgres(?:ql)?\b|\bsupabase\b/i],
  ['database', /\bdatabase\b|\bsql\b|\bpostgres(?:ql)?\b|\bsupabase\b/i],
  ['stripe', /\bstripe\b/i],
  ['clerk', /\bclerk\b/i],
  ['python', /\bpython\b|\bpytest\b/i],
  ['performance', /\bslow\b|\blag(?:gy)?\b|\bperformance\b|\boptimi[sz](?:e|ation|ing)\b|\brendering\b/i],
  ['debugging', /\bdebug(?:ging)?\b|\bbugs?\b|\bcrash(?:es|ing)?\b|\bbroken\b|\bfix\b|\bfail(?:s|ing|ure)?\b/i],
  ['testing', /\btests?\b|\btesting\b|\btdd\b|\bpytest\b/i],
  ['accessibility', /\baccessib\w*\b|\bvoiceover\b|\bwcag\b/i],
  ['design', /\bdesign\b|\bui\b|\blayout\b|\blanding page\b/i],
  ['authentication', /\bauth(?:entication|orization)?\b|\blogin\b|\bsign in\b|\boauth\b|\bclerk\b/i],
  ['payments', /\bpayments?\b|\bbilling\b|\bcheckout\b|\bstripe\b/i],
  ['deployment', /\bdeploy(?:ment|ing)?\b|\bhosting\b|\bci cd\b/i],
  ['seo', /\bseo\b|\bsearch engine\b/i],
  ['security', /\bsecurity\b|\bvulnerabilit\w*\b/i],
  ['frontend', /\bcss\b|\bhtml\b|\bfrontend\b|\bweb\b|\blanding page\b/i],
];

export const capabilities = ['performance', 'accessibility', 'authentication', 'payments', 'security', 'testing', 'design', 'deployment', 'seo', 'debugging'];
export const platforms = ['nextjs', 'react', 'react-native', 'vue', 'angular', 'swift', 'postgres', 'python'];
export const domains = [...platforms, 'database', 'stripe', 'clerk', 'frontend'];

export function signals(text, { task = false } = {}) {
  const normalized = text.replace(/[-_]/g, ' ');
  const tags = rules.filter(([, regex]) => regex.test(normalized)).map(([tag]) => tag);
  // React Native does not imply React DOM or a browser environment.
  if (tags.includes('react-native') && !tags.includes('frontend') && !tags.includes('nextjs')) {
    const react = tags.indexOf('react');
    if (react !== -1) tags.splice(react, 1);
  }
  if (task) {
    if (tags.includes('nextjs') && !tags.includes('react')) tags.push('react');
    if (tags.some(t => ['react', 'nextjs', 'vue', 'angular'].includes(t)) && !tags.includes('frontend')) tags.push('frontend');
  }
  return tags;
}

export function compatible(candidateTags, requested) {
  const specific = candidateTags.filter(t => platforms.includes(t));
  if (specific.length && !specific.some(t => requested.has(t))) return false;
  if (!specific.length && candidateTags.includes('frontend') && !requested.has('frontend')) return false;
  if (candidateTags.includes('database') && !requested.has('database')) return false;
  // Named services should not be introduced just because a framework matches.
  for (const service of ['stripe', 'clerk']) {
    if (candidateTags.includes(service) && !requested.has(service)) return false;
  }
  return true;
}

const labels = { nextjs: 'Next.js', react: 'React', 'react-native': 'React Native', vue: 'Vue', angular: 'Angular', swift: 'Swift', postgres: 'Postgres', python: 'Python', stripe: 'Stripe', clerk: 'Clerk', frontend: 'web UI' };
export const label = tag => labels[tag] ?? tag;
