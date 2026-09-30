# Context-aware recommendation

A short message is not a complete task. `Pokračuj`, `Continue`, `Oprav to` and acknowledgements now resolve against the supplied active conversation before effort and skill selection. Analysis does not store chat memory globally.

## Input and output

`POST /analyze` accepts optional `context` alongside the latest `prompt`:

```json
{
  "prompt": "Pokračuj.",
  "app": "Claude Code",
  "context": {
    "conversationId": "current-chat",
    "source": "manual",
    "messages": [
      {"role": "user", "content": "Migrate Swift actor isolation and fix Sendable race conditions."}
    ],
    "truncated": false
  }
}
```

Sources: `manual`, `accessibility`, `claude-transcript`. Roles: `user`, `assistant`, `context` (unstructured visible text). Bounds: 16 messages, 8,000 UTF-16 units per message and 24,000 total, with a 192 KiB HTTP body ceiling. Unknown fields, sources and roles are rejected. Context is not returned in responses, written to logs, sent to search, or persisted.

`analysis.context` reports `used`, `missing`, `not-needed` or `unavailable`, plus selected input record count, truncation, and source when used. For unstructured input the count denotes chunks, not reconstructed chat turns. Missing context on a continuation yields provisional medium effort, never a confident low-effort assessment. The UI shows missing or partial context and lets the user inspect, replace or clear it.

## Resolution and selection

1. Normalize supported Czech and English task vocabulary.
2. Identify a continuation or a specialty request missing its platform.
3. Walk back through underspecified user turns to the latest scoped task or explicit topic boundary; use later assistant text as supporting data.
4. Inherit missing technology and the ongoing specialty for generic continuation/fix requests. A specific request such as adding tests focuses on testing while keeping stack and complexity.
5. Keep active user exclusions and opt-outs. Historical skill invocations do not become current explicit invocations.
6. Expand supported outcomes: a modern website needs design; enterprise work raises architecture, testing and security needs; authentication plus subscriptions increases effort. A named provider is never invented.
7. Match these needs against compiled SKILL.md profiles, the existing 12 weighted criteria, prerequisites and content evidence. Select up to three complementary supported skills.
8. Determine effort from the current work and active context. An explicit typo fix narrows effort; a new topic or self-contained different platform stops inheritance.

This is bounded deterministic resolution, not general semantic understanding. It can miss unknown technologies, complex topic transitions, ambiguous pronouns, and task changes hidden in unstructured history. It does not infer which steps have already been completed. Missing matches are reported as insufficient evidence, not as proof that the task needs no skills. A model-based task summary plus evidence-checked profiles remains the recommended next stage in the [proposal](SKILL_INTELLIGENCE_PROPOSAL.cs.md).

## Client adapters

- **Claude Code:** the command hook reads only `transcript_path` supplied by `UserPromptSubmit`; it does not discover or scan other transcripts. Absolute regular `.jsonl` files only, with symlink rejection and a 256 KiB tail limit. Records must match `session_id`; active `parentUuid` ancestry excludes sibling branches and sidechains. Tool-only nodes retain ancestry, but tool results, tool calls and thinking are excluded from context. The current submitted prompt is removed if already appended. Truncated, unsupported or missing transcripts are handled without blocking the prompt. Internal transcript record structure is best-effort and not guaranteed by the public hook contract; a real Claude session still needs validation. The supplied filename need not equal the session ID. See the [official hook fields](https://code.claude.com/docs/en/hooks#userpromptsubmit).
- **macOS:** only recognized Cursor/Codex composers are eligible for automatic context extraction. The reader searches at most seven ancestors for a labeled conversation container, never the whole window. It walks recent static text with a 240-node/10-depth/150-ms budget and excludes editors, sidebars, navigation, hidden nodes, terminal and input fields. These snapshots are always marked partial. If the host does not expose a suitable tree, no automatic history is claimed; manual context is available. This adapter has compiled policy/lifecycle tests; actual host AX tree compatibility has not been verified.
- **Lifecycle:** context travels with each capture and request. A context change invalidates recommendations even when the prompt is identical. Missing capture context clears the prior capture. Revision/cancellation checks reject stale responses. Editing context pauses live capture. Copying a prompt does not copy chat history. Automatic analysis waits 300 ms after a settled change; skill selection itself uses the prepared local index.

## Regression coverage

`api/test/context.test.js` covers short Czech/English continuations, specialty inheritance, multi-turn references, separate chats, missing context, narrower work, topic boundaries, explicit constraints, payload limits, localhost HTTP, transcript ancestry, truncation and safe failure. Swift context tests cover serialization, Unicode limits, container boundaries, propagation, copy behavior, invalidation, cancellation and clearing. Synthetic fixtures are not a production accuracy estimate.
