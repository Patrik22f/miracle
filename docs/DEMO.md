# A one-minute demo

1. Start `npm start` and open the built Preflight app.
2. Enable Accessibility once. Focus Cursor's prompt input.
3. Type: “Optimize this Next.js page. It is slow when rendering 500 products.”
4. Press **⌥⌘Return**. If AX cannot read that input, paste the prompt into Preflight.
5. Show the recommended React skill, explanation, and secondary effort/model suggestions.
6. Select the skill and click **Copy with skills**. Paste back into Cursor and review before sending.
7. Explain: “I didn't search for this skill. I just wrote my prompt.”

Fallback: menu bar → Try demo. This is labeled fixture data and works without a backend or internet. Never present fixture data as live discovery.

## Manual acceptance before pitching

- Menu item and global shortcut open the same overlay.
- Capture occurs before the overlay takes focus; selected text wins.
- Empty, inaccessible, and secure inputs have a useful fallback.
- Permission denial does not prevent manual paste.
- Loading can be canceled; editing clears stale results.
- A plain greeting produces no skill; a React performance task produces the React skill.
- Live search and catalog fallback are clearly distinguished.
- Copy action includes only selected links; original prompt is preserved.
- Escape/Close dismisses the overlay; quitting removes the global hotkey.

## Next work, in order

**UI lane:** validate Cursor input capture on the demo machine → refine overlay/keyboard flow → explicit project selection and installation UI.

**Intelligence lane:** ten-prompt relevance evaluation → fetch top candidates' SKILL.md with bounded public-source requests → optional LLM reranker with schema validation, timeout, and deterministic fallback.

**Together:** one supported Cursor install-and-send flow. Review the full skill package, avoid shell interpolation of remote metadata, require a selected project directory, and confirm host skill loading before presenting “Apply & Send”.

Leave accounts, payments, crawling, universal host support, model routing, and hosted infrastructure out of this hackathon iteration.
