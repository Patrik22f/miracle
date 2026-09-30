import { promptCriteria } from './criteria.js';

export const contextLimits = { turns: 16, characters: 24000, messageCharacters: 8000 };
export function validateContext(value) {
  if (value === undefined) return null;
  if (!value || typeof value !== 'object' || Array.isArray(value)) return 'context must be an object.';
  if (Object.keys(value).some(key => !['conversationId', 'source', 'messages', 'truncated'].includes(key))) return 'Unknown context field.';
  if (typeof value.conversationId !== 'string' || !value.conversationId.trim() || value.conversationId.length > 200) return 'context.conversationId must contain 1–200 characters.';
  if (!['manual', 'accessibility', 'claude-transcript'].includes(value.source)) return 'Invalid context source.';
  if (value.truncated !== undefined && typeof value.truncated !== 'boolean') return 'context.truncated must be boolean.';
  if (!Array.isArray(value.messages) || value.messages.length > contextLimits.turns) return 'context.messages must contain at most 16 messages.';
  let size = 0;
  for (const message of value.messages) {
    if (!message || typeof message !== 'object' || Array.isArray(message) || Object.keys(message).some(key => !['role', 'content'].includes(key))
      || !['user', 'assistant', 'context'].includes(message.role) || typeof message.content !== 'string'
      || !message.content.trim() || message.content.length > contextLimits.messageCharacters) return 'Invalid context message (maximum 8000 characters).';
    size += message.content.length;
  }
  return size > contextLimits.characters ? 'Chat context exceeds 24000 characters.' : null;
}

export function normalizeTask(prompt) {
  return prompt.normalize('NFD').replace(/\p{M}/gu, '')
    .replace(/\b(?:bez skillu|zadne skilly|nedoporucuj skilly)\b/gi, ' no skills ')
    .replace(/\b(?:nepouzivej|nepouzij|nikoli|krome)\b/gi, ' do not use ')
    .replace(/\b(?:oprav\w*|chyba|chybu|chyby|pada|nefunguje)\b/gi, ' fix bug ')
    .replace(/\b(?:zrychl\w*|pomal\w*|vykon\w*|optimaliz\w*)\b/gi, ' optimize slow performance ')
    .replace(/\b(?:pristupnost\w*|pristupny|pristupne)\b/gi, ' accessibility ')
    .replace(/\b(?:vytvor\w*|napis|pridej|implementuj)\b/gi, ' create ')
    .replace(/\b(?:uprav\w*|zmen\w*|refaktor\w*)\b/gi, ' edit refactor ')
    .replace(/\b(?:zkontroluj|zkontrolovat|prover\w*)\b/gi, ' review ')
    .replace(/\b(?:soub[e]?znost|soub[e]?zne)\b/gi, ' concurrency ')
    .replace(/\b(?:testy|testovani|otestuj)\b/gi, ' testing ')
    .replace(/\b(?:tabulku|tabulka|tabulky)\b/gi, ' spreadsheet ')
    .replace(/\b(?:prezentaci|prezentace)\b/gi, ' slide deck ')
    .replace(/\barchitektur\w*\b/gi, ' architecture ')
    .replace(/\bmigrac\w*\b/gi, ' migration ')
    .replace(/\b(?:prihlas\w*|log in|sign up)\b/gi, ' authentication ')
    .replace(/\b(?:predplatn\w*|subscription\w*|platby|placeni)\b/gi, ' payments ')
    .replace(/\b(?:zamrza|zasekava|freezes?|unresponsive|janky)\b/gi, ' slow performance debugging ')
    .replace(/\b(?:webovou stranku|webove stranky|website|web site)\b/gi, ' web design ');
}
const fold = text => text.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase();
const unique = values => [...new Set(values)];
// A skill invocation in past prose is not a statement about the task's stack.
const historicalText = text => normalizeTask(text.replace(/(?:^|\s)[$/][a-zA-Z][\w:.-]*/g, ' '));
const followup = /\b(?:continue|proceed|go ahead|do it|do that|fix it|fix this|test it|implement (?:it|that|this)|same|as discussed|next step|this (?:error|screen|code|app|project)|pokracuj|udelej to|oprav to|otestuj to|dokonci to|implementuj to|dalsi krok|stejne|v tom|tento|tuhle|tuhle chybu|tohle)\b/i;
const acknowledgement = /^(?:yes|yeah|yep|ok(?:ay)?|sure|ano|jo|jasne|dobre)[.!\s]*$/i;
const resetTopic = /\b(?:new (?:task|topic)|unrelated|forget (?:the |that |everything |previous)|instead|nov[eay] (?:ukol|tema)|zapomen|misto toho)\b/i;
const trivial = /\b(?:typo|spelling|rename (?:this |the |a )?(?:button|variable|label)|say hello|what is \d|preklep|pozdrav|prejmenuj (?:tlacitko|promennou))\b/i;
const software = /\b(?:app|application|aplikac\w*|software|code|kod\w*|function|screen|obrazovk\w*|server|api|web|feature|funkc\w*)\b/i;

// Resolve references from a bounded, request-scoped history. No process-global
// conversation memory, raw history concatenation, or inferred provider choice.
export function resolveTask(prompt, context) {
  const current = normalizeTask(prompt);
  const raw = fold(prompt);
  const currentTask = promptCriteria(current);
  const continues = followup.test(raw) || acknowledgement.test(raw);
  const narrows = trivial.test(raw);
  const reset = resetTopic.test(raw);
  const valid = !validateContext(context);
  const messages = valid ? context?.messages ?? [] : [];
  const wantsContext = !reset && !narrows && (continues || (currentTask.purposes.length > 0 && currentTask.scopes.length === 0));
  let selected = [];
  if (wantsContext && messages.length) {
    // Walk back through underspecified follow-ups to the latest scoped task.
    // A topic reset is a boundary, even when it has no recognized technology.
    let anchor = -1;
    for (let i = messages.length - 1; i >= 0; i--) {
      if (messages[i].role !== 'user') continue;
      const text = fold(messages[i].content);
      anchor = i;
      if (resetTopic.test(text) || promptCriteria(historicalText(text)).scopes.length) break;
    }
    selected = messages.slice(anchor >= 0 ? anchor : Math.max(0, messages.length - 4));
  }
  const historical = selected.map(row => historicalText(row.content)).join('\n');
  const historicalTask = promptCriteria(historical);
  const historicalConstraints = promptCriteria(selected.filter(row => row.role !== 'assistant').map(row => normalizeTask(row.content)).join('\n'));
  const exclusions = [...currentTask.exclusions, ...historicalConstraints.exclusions];
  const excludedScopes = unique(exclusions.flatMap(text => promptCriteria(text.replace(/\b(?:do not|don't|not|without|avoid|exclude)\b/gi, '')).scopes));
  const inheritedScopes = currentTask.scopes.length ? [] : historicalTask.scopes.filter(scope => !excludedScopes.includes(scope));
  const inheritedPurposes = continues && currentTask.purposes.every(purpose => ['debugging', 'refactoring'].includes(purpose)) ? historicalTask.purposes : [];
  const needs = [];
  const goal = `${currentTask.positive}\n${continues ? historicalTask.positive : ''}`;
  // Expand outcomes into useful work, while preserving explicit platform choices.
  if (/\b(?:production ready|production-ready|enterprise|produkcn\w*)\b/i.test(goal)) needs.push('architecture', 'testing', 'security');
  if (/\bweb\b/i.test(goal) && /\b(?:create|modern|redesign|design|beautiful)\b/i.test(goal)) needs.push('design');
  if (/\b(?:slow|performance)\b/i.test(goal) && ![...currentTask.scopes, ...inheritedScopes].length) needs.push('debugging');
  const facts = unique([...inheritedScopes, ...inheritedPurposes, ...needs]);
  const technical = software.test(goal) || facts.some(tag => !['pdf', 'documents', 'spreadsheets', 'presentations'].includes(tag));
  const effectivePrompt = current + (facts.length ? `\n${technical ? 'Software task. ' : ''}${facts.join(' ')}.` : '');
  const task = promptCriteria(effectivePrompt);
  task.exclusions = unique(exclusions);
  task.abstain ||= historicalConstraints.abstain;
  task.workflowText = `${currentTask.positive}\n${historicalTask.positive}`;
  // Historical vocabulary supports evidence retrieval, but never controls explicit
  // invocation, exclusions, or execution. Bound it to the active task's words.
  if (selected.length) task.tokens = unique([...task.tokens, ...historicalTask.tokens]).slice(0, 160);
  const used = selected.length > 0;
  const status = used ? 'used' : wantsContext ? 'missing' : messages.length ? 'not-needed' : 'unavailable';
  const complexityText = `${current}\n${used ? historical : ''}`;
  let level = 'low', reason = 'A small, self-contained task needs little investigation.';
  if (narrows) { level = 'low'; reason = 'The latest request narrows the work to a small, explicit edit.'; }
  else if (/\b(?:architect\w*|migration|migrat\w*|distributed|race condition|data race|enterprise|production[- ]ready|multi[- ]tenant|refactor\w*[\s\S]{0,40}(?:entire|whole|cele))\b/i.test(complexityText)
    || (task.purposes.includes('authentication') && task.purposes.includes('payments')) || task.purposes.length >= 3) {
    level = 'high'; reason = used ? 'The chat describes a complex task; this short prompt continues that work.' : 'This task spans architecture, coordinated changes, or multiple interacting concerns.';
  } else if (continues && !used) {
    level = 'medium'; reason = 'This refers to earlier work, but its chat context is unavailable. Effort is provisional.';
  } else if (used || task.scopes.length || task.purposes.length || software.test(current) || current.length > 600) {
    level = 'medium'; reason = used ? 'Effort includes the active task from the chat, not just the latest sentence.' : 'This task needs implementation, investigation, or a structured deliverable.';
  }
  return { effectivePrompt, task, effort: { level, reason }, context: {
    status, ...(used ? { source: context.source } : {}), turnCount: selected.length, truncated: used && Boolean(context.truncated),
  } };
}
