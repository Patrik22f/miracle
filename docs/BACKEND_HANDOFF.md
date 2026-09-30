# Integrated project handoff — 2026-09-30

Backend and macOS UI work are integrated on `main` in [Patrik22f/miracle](https://github.com/Patrik22f/miracle/tree/main). This includes the new API behavior, Swift contracts, Miracle branding, model recommendations, selected skill installation and the Shopfront demo. Continue from `main`; no cross-feature merge is required.

## Get running

Requires Node 22+. The macOS client additionally needs macOS 14+ and Xcode 16+ / Swift 6. There are no npm dependencies to install.

```sh
git fetch origin
git switch main
git pull --ff-only origin main
cp .env.example .env # fresh checkout only; preserve an existing .env
npm run skills:import -- --local-only
npm start
```

The backend listens on `http://127.0.0.1:8787`; `GET /health` reports its mode. Local skill matching needs no key. The local-only import indexes this machine's installed skills; an empty local library can return no recommendations. Use `npm run skills:import` to include the configured public starter skills.

For optional next-task suggestions, set `GROQ_API_KEY` in the local `.env`, restart the backend, and select a project in the client. Selected code excerpts and prompt/chat context are sent to Groq. Official skills.sh API imports require a separate `VERCEL_OIDC_TOKEN`; neither credential is part of this handoff. See [prompt suggestions](PROMPT_SUGGESTIONS.md) and [skill matching](SKILL_MATCHING.md).

In a second terminal, quit any running Miracle or older Preflight app, then run `npm run macos:build` and `open build/Miracle.app`. The build uses an Apple Development certificate; see the [build and signing notes](../README.md). Demo mode works without the backend.

## Integration points

- `POST /analyze`: bounded prompt/chat context, combined skill filters, `maxSkills` from 0 to 8, and `meta.bestSkillId` (`null` when no match qualifies).
- `GET /skills`: searchable imported library with availability, source, scope and purpose filters. `POST /skills/import` refreshes the configured imports.
- `POST /suggestions`: exactly three validated project-aware suggestions when ready; explicit `setup`, `empty`, `waiting` and `error` states otherwise. Includes caching, request coalescing, cooldowns and timeouts.
- `npm run --silent skills:find -- "task" --app Codex`: local CLI lookup. Claude Code integration is documented in [CLAUDE_CODE.md](CLAUDE_CODE.md).
- Shared JSON schemas and fixtures live in `contracts/`; Swift types live in `Contract.swift` and `PromptSuggestions.swift`. Keep these synchronized. The [API guide](API.md) describes request and response shapes.

## Continue from the merged version

The merge combines backend commit `8e6c2c7` with UI commit `93076d2` and retains both histories. Older feature branches remain available as historical references.

With a clean checkout, start any further work from the latest shared branch:

```sh
git fetch origin
git switch main
git pull --ff-only origin main
```

Conflict resolution preserves automatic host detection, read-only model/effort recommendations, the single-line captured prompt and demo installations that only affect session state. The review includes project suggestions and chat context. **Use draft** pauses capture, retains the detected host for recommendations, and exposes draft editing/copying plus **Resume live capture**. Demo follows real prompts and uses the local skill catalog. Its suggested prompts use Groq with the bundled Shopfront source and presentation brief, without changing the normally selected project.

For UI acceptance, check prompt capture and focus behavior in Cursor/Codex, model/skill display, project selection, suggestion loading/error/empty states, Use draft, Copy prompt, settings and permission onboarding. Live Groq calls were not repeated for this merge.

## Verification at handoff

- `npm test`: 148 passed.
- `npm run macos:test`: 78 passed, including demo/backend integration and preserving the detected host for suggested drafts.
- `npm run eval`: 30/30 controlled relevance cases passed.
- `npm run eval:knowledge`: 28/28 controlled knowledge cases passed.
- `git diff --check`: passed.

Provider behavior was tested with mocked responses; these checks do not claim live-provider availability or production ranking accuracy. `.env`, `.preflight/`, build outputs and local caches remain ignored.

The normal installation build stopped because an older application was running. A separate test bundle was assembled from the tested executable and resources and passed strict ad-hoc signature verification. After explicit launch approval, onboarding, General/Prompts/Models settings, host model catalogs and the bundled Shopfront website were verified in the running test app. It used a separate preferences domain; the installed application was left untouched. This smoke check does not establish end-to-end capture permissions or live Groq availability for the merged build.
