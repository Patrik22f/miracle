// Deliberately explainable, local criteria. Skill bodies are data, never instructions.
const scopeRules = [
  ['swiftui', /\bswiftui\b/i], ['uikit', /\buikit\b/i], ['appkit', /\bappkit\b/i],
  ['swiftdata', /\bswiftdata\b/i], ['core-data', /\bcore data\b/i],
  ['swift', /\bswift\b|\bsendable\b|\bmainactor\b/i],
  ['apple', /\bios\b|\bipados\b|\bmacos\b|\bwatchos\b|\bapple\b|\bxcode\b|\btestflight\b|\bapp store\b|\bvoiceover\b|\bwidgetkit\b|\bhealthkit\b/i],
  ['react-native', /\breact native\b|\bexpo\b|\bflatlist\b/i],
  ['nextjs', /\bnext(?:\.?js| js)\b/i], ['react', /\breact\b/i],
  ['vue', /\bvue\b|\bnuxt\b/i], ['angular', /\bangular\b/i],
  ['web', /\bweb\b|\bfrontend\b|\bhtml\b|\bcss\b|\blanding page\b/i],
  ['supabase', /\bsupabase\b/i], ['postgres', /\bpostgres(?:ql)?\b/i],
  ['database', /\bdatabase\b|\bsql\b/i], ['python', /\bpython\b|\bpytest\b/i],
  ['grdb', /\bgrdb\b/i], ['sqlite', /\bsqlite\b/i],
  ['stripe', /\bstripe\b/i], ['clerk', /\bclerk\b/i],
  ['pdf', /\bpdf\b/i], ['documents', /\bdocx\b|\bword document\b/i],
  ['spreadsheets', /\bxlsx\b|\bspreadsheet\w*\b|\bexcel\b/i],
  ['presentations', /\bpptx\b|\bpowerpoint\b|\bslide deck\b/i],
  ['openai', /\bopenai\b|\bcodex\b|\bchatgpt\b/i],
];
const purposeRules = [
  ['accessibility', /\baccessib\w*\b|\bvoiceover\b|\bwcag\b|\bdynamic type\b/i],
  ['performance', /\bperformance\b|\bslow\b|\blag(?:gy)?\b|\bhitch\w*\b|\boptimi[sz]\w*\b/i],
  ['concurrency', /\bconcurren\w*\b|\basync\b|\bawait\b|\bactors?\b|\bsendable\b|\bmainactor\b|\brace condition\b|\bdata race\b/i],
  ['testing', /\btest(?:s|ing)?\b|\btdd\b|\bpytest\b/i],
  ['debugging', /\bdebug\w*\b|\bcrash\w*\b|\bbugs?\b|\bbroken\b|\bfix\b|\bfail(?:s|ing|ure|ures|ed)\b/i],
  ['persistence', /\bpersist\w*\b|\bdatabase\b|\bstorage\b|\bswiftdata\b|\bcore data\b|\bsql\b/i],
  ['security', /\bsecur\w*\b|\bkeychain\b|\bpasskeys?\b|\bencrypt\w*\b|\bvulnerab\w*\b/i],
  ['authentication', /\bauth(?:entication|orization)?\b|\blogin\b|\boauth\b|\bsign in\b/i],
  ['payments', /\bpayments?\b|\bbilling\b|\bcheckout\b|\bstorekit\b|\bin app purchase\w*\b|\biap\b/i],
  ['networking', /\bnetwork\w*\b|\burlsession\b|\bsockets?\b|\bhttp\b/i],
  ['design', /\bdesign\b|\blayout\w*\b|\bui\b|\blanding page\b|\bliquid glass\b/i],
  ['refactoring', /\brefactor\w*\b|\bsimplif\w*\b/i],
  ['architecture', /\barchitect\w*\b|\bmvvm\b|\btca\b/i],
  ['release', /\brelease\b|\bsubmit\w*\b|\bsubmission\b|\bapp store review\b|\bshipping\b/i],
  ['testflight', /\btestflight\b|\bbeta distribution\b/i],
  ['build', /\bbuild\s+(?:fail\w*|errors?)\b|\bxcodebuild\b|\bcompil\w*\b|\barchive\b/i],
  ['signing', /\bsigning\b|\bprovision\w*\b|\bnotari[sz]\w*\b/i],
  ['metadata', /\bmetadata\b|\baso\b|\bapp store keywords\b/i],
  ['localization', /\blocali[sz]\w*\b|\btranslat\w*\b/i],
  ['screenshots', /\bscreenshots?\b/i], ['simulator', /\bsimulator\b/i],
  ['memory', /\bmemory\b|\bleaks?\b|\bretain cycles?\b|\bmemgraph\b/i],
  ['widgets', /\bwidgets?\b|\bwidgetkit\b/i],
  ['app-intents', /\bapp intents?\b|\bsiri\b|\bapp shortcuts?\b/i],
  ['health', /\bhealthkit\b|\bworkout\w*\b/i],
  ['media', /\bcamera\b|\baudio\b|\bvideo\b|\bphotos?\b/i],
  ['graphics', /\bmetal\b|\bshaders?\b|\bgpu\b|\brealitykit\b/i],
  ['image-generation', /\bgenerate\w* (?:an? )?image\b|\bimagegen\b|\bimage generation\b/i],
  ['focus', /\bfocus(?:engine|ed|able)?\b|\bkeyboard navigation\b/i],
  ['background', /\bbackground (?:execution|tasks?|refresh|processing)\b|\bbgtaskscheduler\b/i],
  ['location', /\blocation\b|\bmapkit\b|\bgeofenc\w*\b|\bgps\b/i],
  ['observability', /\bobservability\b|\blogging\b|\boslog\b|\bsignposts?\b/i],
  ['interface-copy', /\bmicrocopy\b|\bonboarding (?:text|copy)\b|\b(?:error|empty state|button|interface) (?:messages?|text|copy|labels?)\b/i],
  ['skill-authoring', /\b(?:create|write|edit|design)\b[^.!?\n]{0,60}\bskill\b|\bskill creator\b/i],
  ['skill-installation', /\binstall\w* (?:a |the )?skills?\b|\bskill installer\b/i],
];
const normalize = text => text.replace(/[-_]/g, ' ').toLowerCase();
const detect = (text, rules) => rules.filter(([, pattern]) => pattern.test(normalize(text))).map(([id]) => id);
const unique = xs => [...new Set(xs)];
const stop = new Set('use when with this that from into your using about which their should any all for and the are but not only skill skills code app application help work task expert best practices guide guidance write read edit review build fix improve updates writes reviews improves implement implementing building create writing reviewing refactoring development swift swiftui apple ios macos react nextjs web'.split(' '));
const tokens = text => unique(normalize(text).match(/[a-z][a-z0-9]{2,}/g) ?? []).filter(t => !stop.has(t));
const escape = text => text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

export const criteria = [
  { id: 'purpose', label: 'Task purpose', maximum: 30 },
  { id: 'scope', label: 'Platform or artifact', maximum: 25 },
  { id: 'trigger', label: 'Description evidence', maximum: 25 },
  { id: 'specificity', label: 'Specialist fit', maximum: 10 },
  { id: 'availability', label: 'Available instructions', maximum: 10 },
];

function expandScopes(scopes) {
  const out = new Set(scopes);
  if (['swiftui', 'uikit', 'appkit', 'swiftdata', 'core-data', 'swift'].some(s => out.has(s))) { out.add('swift'); out.add('apple'); }
  if (out.has('nextjs')) out.add('react');
  if (['nextjs', 'react', 'vue', 'angular'].some(s => out.has(s))) out.add('web');
  if (out.has('supabase')) out.add('postgres');
  if (out.has('postgres')) out.add('database');
  return [...out];
}

function scopesFor(text) {
  let scopes = detect(text, scopeRules);
  if (scopes.includes('react-native') && !/\b(?:browser|dom|next\.?js|web)\b/i.test(text)) scopes = scopes.filter(s => s !== 'react');
  return scopes;
}

export function promptCriteria(prompt) {
  const exclusions = [];
  const positive = prompt.replace(/\b(?:do not|don't|without|avoid|exclude|not)\s+[^,;.\n]+/gi, part => { exclusions.push(part); return ' '; });
  return {
    positive, exclusions,
    scopes: expandScopes(scopesFor(positive)),
    purposes: detect(positive, purposeRules),
    tokens: tokens(positive),
    abstain: /\b(?:no skills?|without (?:any )?skills?|do not recommend skills?|don't recommend skills?)\b/i.test(prompt),
  };
}

// These are reviewed scope annotations, not evidence inferred from repository owners.
const overrides = {
  'vercel-react-best-practices': { scopes: ['react', 'nextjs'], purposes: ['performance'] },
  'web-design-guidelines': { scopes: ['web'], purposes: ['design', 'accessibility'] },
  'frontend-design': { scopes: ['web'], purposes: ['design'] },
  'supabase-postgres-best-practices': { scopes: ['postgres'], purposes: ['performance', 'persistence'] },
  'systematic-debugging': { scopes: [], purposes: ['debugging'] },
  'test-driven-development': { scopes: [], purposes: ['testing'] },
  'asc-release-flow': { scopes: ['apple'], purposes: ['release'] },
  'asc-testflight-orchestration': { scopes: ['apple'], purposes: ['testflight'] },
  'asc-xcode-build': { scopes: ['apple'], purposes: ['build'] },
  'axiom-fix-build': { scopes: ['apple'], purposes: ['build'] },
  'axiom-optimize-build': { scopes: ['apple'], purposes: ['build'] },
  'swiftui-expert-skill': { scopes: ['swiftui'], purposes: [] },
  'swiftui-pro': { scopes: ['swiftui'], purposes: [] },
  'axiom-swiftui': { scopes: ['swiftui'], purposes: [] },
  'axiom-swift': { scopes: ['swift'], purposes: [] },
  'docx': { scopes: ['documents'], purposes: [] },
  'documents': { scopes: ['documents'], purposes: [] },
  'xlsx': { scopes: ['spreadsheets'], purposes: [] },
  'spreadsheets': { scopes: ['spreadsheets'], purposes: [] },
  'pptx': { scopes: ['presentations'], purposes: [] },
  'presentations': { scopes: ['presentations'], purposes: [] },
  'pdf': { scopes: ['pdf'], purposes: [] },
  'imagegen': { scopes: [], purposes: ['image-generation'] },
  'writing-for-interfaces': { scopes: [], purposes: ['interface-copy'] },
  'background-execution': { scopes: ['apple'], purposes: ['background'] },
  'app-intents': { scopes: ['apple'], purposes: ['app-intents'] },
  'widgets': { scopes: ['apple'], purposes: ['widgets'] },
  'stripe-best-practices': { scopes: ['stripe'], purposes: ['payments', 'authentication', 'security', 'testing'] },
};

const prerequisites = {
  'figma-to-swiftui': /\bfigma\b/i,
  'axiom-test-simulator': /\bsimulator\b|\bui tests?\b|\bend to end\b/i,
  'ios-code-audit': /\baudit\b|\breview\b|\binspect\b/i,
  'axiom-ai': /\b(?:apple intelligence|on device ai|foundation models|languagemodelsession|generable|coreml|speechtranscriber|speech to text)\b/i,
  'axiom-tools': /\baxiom\b|\bxclog\b|\bsymbolicat\w*\b/i,
  'excel-live-control': /\b(?:open|active|live|connected)\b[\s\S]{0,40}\b(?:excel|workbook|session)\b|\bexcel\b[\s\S]{0,40}\b(?:add in|open|active|live|connected)\b|@excel/i,
  'connect-recommend': /\bstripe connect\b|\bconnected accounts?\b|\bmarketplace\b|\bsellers?\b|\bvendors?\b|\bsplit payments?\b|\brevenue sharing\b/i,
  'connect-required-verification-information': /\bstripe connect\b|\bconnected accounts?\b|\bkyc\b|\bsellers?\b|\bmerchants?\b/i,
  'stripe-apps': /\bstripe apps?\b|\bstripe dashboard\b|\bui extension\b|\bstripe app.yaml\b/i,
  'stripe-pay': /\bsend funds\b|\btransfer money\b|\bpay (?:a |the )?(?:stripe|business|merchant)\b|\bstripe profile\b/i,
  'upgrade-stripe': /\bupgrad\w*\b|\bmigrat\w*\b|\bapi versions?\b/i,
};

export function skillCriteria(skill) {
  const name = skill.name.toLowerCase();
  if (overrides[name]) return { ...overrides[name], tokens: tokens(skill.description), annotated: true };
  const nameScopes = scopesFor(skill.name);
  const description = skill.description.split(/\b(?:do not use|don't use|not for|avoid using)\b/i)[0];
  let scopes = nameScopes.length ? nameScopes : /^(axiom-|asc-|ios-)/.test(name) ? ['apple'] : scopesFor(description);
  // A SwiftUI/SwiftData specialist must match that framework, not just the word Swift.
  if (scopes.some(s => ['swiftui', 'uikit', 'appkit', 'swiftdata', 'core-data'].includes(s))) scopes = scopes.filter(s => !['swift', 'apple'].includes(s));
  if (/^(axiom-|asc-|ios-|swift-|app-store-|appstore-|apple-)/.test(skill.name) && !scopes.length) scopes = ['apple'];
  const namePurposes = detect(skill.name, purposeRules);
  const purposes = namePurposes.length ? namePurposes : detect(description, purposeRules);
  return { scopes, purposes, tokens: tokens(`${skill.name} ${description}`), annotated: false };
}

export function evaluateSkill(skill, task, profile = skillCriteria(skill)) {
  const named = new RegExp(`(?:^|[^a-z0-9-])\\$?${escape(skill.name)}(?:$|[^a-z0-9-])`, 'i');
  // A common format name such as PDF is not itself an invocation of the pdf skill.
  const invocation = new RegExp(`\\$${escape(skill.name)}(?:$|[^a-z0-9-])|\\b${escape(skill.name)}\\s+skill\\b|\\bskill\\s+${escape(skill.name)}\\b`, 'i');
  const explicit = invocation.test(task.positive) || (/[-_:]/.test(skill.name) && named.test(task.positive));
  const rejected = reason => ({ skill, score: 0, eligible: false, reason, evidence: [], coverage: [] });
  if (task.abstain) return rejected('The prompt asks for no skills.');
  if (task.exclusions.some(text => named.test(text))) return rejected('The prompt excludes this skill.');
  const matchedScopes = profile.scopes.filter(s => task.scopes.includes(s));
  const matchedPurposes = profile.purposes.filter(s => task.purposes.includes(s));
  const matchedTokens = profile.tokens.filter(t => task.tokens.includes(t));
  // Unclassified workflows still need concrete description evidence. This path
  // never bypasses a platform, named provider, prerequisite, or specialty gate.
  const lexical = !profile.purposes.length && matchedTokens.length >= 2;
  if (!explicit) {
    const prerequisite = prerequisites[skill.name.toLowerCase()];
    if (prerequisite && !prerequisite.test(normalize(task.workflowText ?? task.positive))) return rejected('The required workflow is absent from the prompt.');
    if (profile.scopes.length && !matchedScopes.length) return rejected('Platform or artifact does not match.');
    // Named providers must match even when another scope (e.g. React) does.
    if (profile.scopes.some(s => ['stripe', 'clerk', 'supabase'].includes(s) && !task.scopes.includes(s))) return rejected('Required service is absent.');
    if (profile.purposes.length && !matchedPurposes.length) return rejected('The task does not need this specialty.');
    if (!profile.purposes.length && task.purposes.length && !lexical && !['pdf', 'documents', 'spreadsheets', 'presentations'].some(s => matchedScopes.includes(s))) return rejected('A broad skill does not establish a specialist match.');
    if (!profile.scopes.length && !profile.annotated && (!skill.content || (!matchedPurposes.length && !lexical))) return rejected('Insufficient scope evidence.');
    if (!matchedScopes.length && !matchedPurposes.length && !lexical) return rejected('No task evidence.');
    // General debugging/testing should still be about technical work.
    if (!lexical && !profile.scopes.length && !task.scopes.length && matchedPurposes.some(p => ['debugging', 'testing'].includes(p))
      && !/\b(?:code|function|test|software|compiler|stack trace|server|api)\b/i.test(task.positive)) return rejected('No technical task context.');
  }
  const values = explicit ? [30, 25, 25, 10, 10] : [
    matchedPurposes.length ? 30 : 20,
    matchedScopes.length ? (matchedScopes.some(s => !['swift', 'apple', 'web', 'database'].includes(s)) ? 25 : 20) : 15,
    Math.min(25, matchedTokens.length * 5),
    profile.purposes.length > 0 && profile.purposes.length <= 2 ? 10 : 5,
    skill.provenance === 'installed' ? 10 : skill.content ? 7 : 0,
  ];
  const evidence = criteria.map((criterion, i) => ({ ...criterion, points: values[i] }));
  const score = values.reduce((a, b) => a + b, 0);
  const contexts = task.scopes.filter(scope => !task.scopes.some(other => other !== scope && expandScopes([other]).includes(scope)));
  const applicable = contexts.filter(context => !profile.scopes.length || expandScopes([context]).some(scope => profile.scopes.includes(scope)));
  const topics = matchedPurposes.length ? [...matchedPurposes] : lexical && !profile.scopes.length ? matchedTokens.map(t => `workflow-${t}`) : ['general'];
  if (matchedPurposes.some(p => p !== 'debugging') && task.purposes.includes('debugging')) topics.push('debugging');
  const coverage = topics.flatMap(topic => (applicable.length ? applicable : ['general']).map(context => `${context}:${topic}`));
  const reason = explicit ? `You explicitly requested ${skill.name}.` : `Matches ${matchedPurposes.join(' and ') || (lexical ? matchedTokens.slice(0, 3).join(', ') : 'the requested artifact or framework')}${matchedScopes.length ? ` for ${matchedScopes.join(' / ')}` : ''}.`;
  return { skill, eligible: score >= 60, score, reason, evidence, coverage, explicit, matchedTokens };
}

export function recommendSkills(candidates, prompt, maxSkills = 3) {
  const task = promptCriteria(prompt);
  const evaluated = candidates.map(skill => evaluateSkill(skill, task)).filter(row => row.eligible)
    .sort((a, b) => Number(b.explicit) - Number(a.explicit) || b.score - a.score
      || b.evidence[1].points - a.evidence[1].points
      || Number(b.skill.provenance === 'installed') - Number(a.skill.provenance === 'installed')
      || a.skill.id.localeCompare(b.skill.id));
  const chosen = [], covered = new Set(), names = new Set();
  for (const row of evaluated) {
    if (chosen.length >= maxSkills) break;
    if (names.has(row.skill.name.toLowerCase())) continue;
    if (!row.explicit && row.coverage.every(topic => covered.has(topic))) continue;
    chosen.push(row); names.add(row.skill.name.toLowerCase());
    row.coverage.forEach(topic => covered.add(topic));
  }
  return chosen.map(({ skill, score, reason, evidence }) => ({
    id: skill.id, name: skill.name, source: skill.source, description: skill.description,
    url: skill.url, repositoryUrl: skill.repositoryUrl, installs: skill.installs ?? null,
    provenance: skill.provenance, security: 'not-audited', confidence: score / 100,
    reason, evaluation: { score, threshold: 60, criteria: evidence },
  }));
}
