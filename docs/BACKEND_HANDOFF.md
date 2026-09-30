# Backend handoff — 2026-09-30

Backend work is ready for the UI teammate on `feature/backend-intelligence` in [Patrik22f/miracle](https://github.com/Patrik22f/miracle/tree/feature/backend-intelligence). This branch includes the Swift contract types and client integration for the new API behavior.

## Get running

Requires Node 22+. The macOS client additionally needs macOS 14+ and Xcode 16+ / Swift 6. There are no npm dependencies to install.

```sh
git fetch origin
git switch feature/backend-intelligence
git pull --ff-only origin feature/backend-intelligence
cp .env.example .env # fresh checkout only; preserve an existing .env
npm run skills:import -- --local-only
npm start
```

The backend listens on `http://127.0.0.1:8787`; `GET /health` reports its mode. Local skill matching needs no key. The local-only import indexes this machine's installed skills; an empty local library can return no recommendations. Use `npm run skills:import` to include the configured public starter skills.

For optional next-task suggestions, set `GROQ_API_KEY` in the local `.env`, restart the backend, and select a project in the client. Selected code excerpts and prompt/chat context are sent to Groq. Official skills.sh API imports require a separate `VERCEL_OIDC_TOKEN`; neither credential is part of this handoff. See [prompt suggestions](PROMPT_SUGGESTIONS.md) and [skill matching](SKILL_MATCHING.md).

In a second terminal, quit any running Preflight app, then run `npm run macos:build` and `open build/Preflight.app`. The build uses an Apple Development certificate; see the [build and signing notes](../README.md). Demo mode works without the backend.

## Integration points

- `POST /analyze`: bounded prompt/chat context, combined skill filters, `maxSkills` from 0 to 8, and `meta.bestSkillId` (`null` when no match qualifies).
- `GET /skills`: searchable imported library with availability, source, scope and purpose filters. `POST /skills/import` refreshes the configured imports.
- `POST /suggestions`: exactly three validated project-aware suggestions when ready; explicit `setup`, `empty`, `waiting` and `error` states otherwise. Includes caching, request coalescing, cooldowns and timeouts.
- `npm run --silent skills:find -- "task" --app Codex`: local CLI lookup. Claude Code integration is documented in [CLAUDE_CODE.md](CLAUDE_CODE.md).
- Shared JSON schemas and fixtures live in `contracts/`; Swift types live in `Contract.swift` and `PromptSuggestions.swift`. Keep these synchronized. The [API guide](API.md) describes request and response shapes.

## Continue on the UI branch

At handoff, `origin/feature/macos-ui` is at `93076d2` and already contains newer UI work, including Miracle branding and Shopfront presentation. This backend branch has separate client integration and still displays Zázrak. Preserve the newer UI design and reconcile the integration during the merge.

With a clean UI checkout, create an integration branch and merge:

```sh
git fetch origin
git switch -c codex/backend-ui-integration origin/feature/macos-ui
git merge origin/feature/backend-intelligence
```

Expect overlapping changes in `AppModel.swift`, the prompt/recommendation views, settings, presentation, app naming and README files. Bring across the suggestion service/UI, updated contract and fixtures, context handling, filters and model catalog integration while retaining the intended UI. Resolve conflicts, then run `npm run check`.

Finish with a manual app pass: prompt capture and focus behavior in Cursor/Codex, model/skill display, project selection, suggestion loading/error/empty states, Use draft, Copy prompt, settings and permission onboarding. A fresh manual UI acceptance pass and live Groq smoke test were not repeated for this GitHub handoff.

## Verification at handoff

- `npm test`: 148 passed.
- `npm run macos:test`: 69 passed.
- `npm run eval`: 30/30 controlled relevance cases passed.
- `npm run eval:knowledge`: 28/28 controlled knowledge cases passed.
- `git diff --check`: passed.

Provider behavior was tested with mocked responses; these checks do not claim live-provider availability or production ranking accuracy. `.env`, `.preflight/`, build outputs and local caches remain ignored.
