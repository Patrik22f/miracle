# A one-minute demo

1. Start `npm start` and open the built Preflight app.
2. Enable Accessibility once and leave **Live capture** on. Focus Cursor's prompt input.
3. Type: “Optimize this Next.js page. It is slow when rendering 500 products.”
4. Show the text appearing automatically in **Your prompt**, then click **Analyze** if automatic analysis is paused. If AX cannot read that input, paste the prompt into Preflight.
5. Show the recommended React skill, explanation, and secondary effort/model suggestions.
6. Select the skill and click **Copy with skills**. Paste back into Cursor and review before sending.
7. Explain: “I didn't search for this skill. I just wrote my prompt.”

Fallback: menu bar → Try demo. This is labeled fixture data and works without a backend or internet. Never present fixture data as live discovery.

## Manual acceptance before pitching

- The menu-bar icon opens the review popover; Settings is a separate window.
- Live capture follows the complete field while typing, pasting, deleting, and switching apps without stealing focus.
- Editing inside Preflight pauses capture; resuming it follows new external text.
- Empty editable fields clear the captured prompt; unsupported controls preserve the last snapshot with a fallback status.
- Permission grants and revocations are reflected without relaunching.
- Empty, inaccessible, and secure inputs have a useful fallback.
- Permission denial does not prevent manual paste.
- Loading can be canceled; editing clears stale results.
- A plain greeting produces no skill; a React performance task produces the React skill.
- Live search and catalog fallback are clearly distinguished.
- Copy action includes only selected links; original prompt is preserved.
- Escape/Close dismisses the review popover.

## Next work, in order

**UI lane:** validate Cursor input capture on the demo machine → refine overlay/keyboard flow → validate the project installation destination and package loading.

**Intelligence lane:** [installed and public imports plus explainable criteria](SKILL_MATCHING.md) are implemented. The thirty-prompt evaluation and live regression checks are in place. Next: extend prerequisite coverage and evaluate unfamiliar task vocabulary against real demo failures; consider a bounded optional semantic reranker only after those cases are measured.

**Together:** one supported Cursor install-and-send flow. Review the full skill package, avoid shell interpolation of remote metadata, require a selected project directory, and confirm host skill loading before presenting “Apply & Send”.

Leave accounts, payments, crawling, universal host support, model routing, and hosted infrastructure out of this hackathon iteration.
