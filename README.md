# Preflight

**The right Agent Skills, before you send.**

A hackathon MVP: focus an AI prompt, press **⌥⌘Return**, and review public skill recommendations in a native macOS overlay. Skills are the product; model and effort are secondary advice.

## Start in two minutes

Requirements: macOS 14+, Xcode 16+ / Swift 6, and Node 22+. No npm packages, API keys, database, or paid services are required.

```sh
cp .env.example .env
npm start
```

In a second terminal, from the same repo:

```sh
npm run macos:build
open build/Preflight.app
```

The sparkle menu-bar item opens the overlay. Click **Accessibility…**, allow **Preflight** in System Settings → Privacy & Security → Accessibility, then focus a prompt in another app and press **⌥⌘Return**. Selected text takes priority over the field's full text. If the input isn't exposed, paste into the overlay and click **Analyze prompt**.

Review the skills, select the ones you want, and click **Copy with skills**. Paste back into your AI app, review, and send. Closing the overlay leaves the original input untouched.

For a UI-only demo, no backend is needed:

```sh
open build/Preflight.app --args --demo
```

Or choose **Try demo** from the menu bar. Demo mode always shows the clearly labeled sample response, regardless of the text. Turn Demo mode off for real analysis. The API can also work offline with `SKILLS_MODE=offline npm start`.

## What's working

- Native SwiftUI overlay, AppKit menu bar, dedicated registered global shortcut.
- Accessibility capture of supported focused text inputs, selected-text preference, secure-field exclusion, paste fallback.
- `POST /analyze` with request validation, bounded input, timeouts, errors, and stable JSON shapes.
- Public skills.sh search, normalization, deduplication, relevance ranking, up to three results, and a valid “no skill needed” result.
- Small public-source catalog fallback with honest provenance and warnings.
- Model capability profile and effort advice; deterministic heuristics keep the demo fast and key-free.
- Shared schemas, example request/response, macOS offline fixture, tests, and CI.

## Two people, two lanes

| Owner | Paths | Branch | First milestone |
| --- | --- | --- | --- |
| UI/macOS teammate | `macos/`, `scripts/build-macos.sh` | `feature/macos-ui` | Verify capture in Cursor, polish overlay and permission onboarding |
| Backend/intelligence teammate | `api/`, `scripts/smoke.js`, `.env.example` | `feature/backend-intelligence` | Improve relevance on ten real prompts; optionally add content-aware reranking |
| Both | `contracts/`, shared README, CI | Agree before editing | Keep request/response compatible |

```sh
git fetch origin
git switch feature/macos-ui                # UI owner
# OR
git switch feature/backend-intelligence   # API owner
```

Both branches start from the same scaffold. Open small PRs to `main`; pull main into your branch after a teammate merges. The UI owner can use Demo mode without waiting for the API owner. See [CONTRIBUTING.md](CONTRIBUTING.md) for the handoff and contract-change checklist.

## Repository map

```text
macos/         Swift package: menu bar, hotkey, focused input, overlay, API client
api/src/       HTTP server, task analysis, skills search and ranking, catalog
api/test/      Offline behavior, upstream failure, API and contract tests
contracts/     JSON Schema v1 and shared fixtures — integration boundary
scripts/       Build the .app bundle and smoke-test the running API
docs/          API guide, demo checklist, next work
.github/       Backend and macOS CI
```

## API example

```sh
curl -s http://127.0.0.1:8787/analyze \
  -H 'Content-Type: application/json' \
  --data @contracts/fixtures/analyze-request.json
```

Request fields: `prompt` (required, 1–12,000 characters), `app` (optional label), `maxSkills` (optional, 0–3). Response: `schemaVersion`, `requestId`, `analysis`, `effort`, `model`, `skills`, `meta`. See [the API guide](docs/API.md) and [response schema](contracts/analyze-response.schema.json).

```sh
npm test                  # offline backend + HTTP + contract checks
npm run macos:test        # build client + decode shared contract in Swift
npm run smoke             # live check against a running API
```

## Public discovery and scope

The adapter uses `https://skills.sh/api/search?q=…&limit=8`, the public endpoint used by the [skills CLI](https://github.com/vercel-labs/skills/blob/main/src/find.ts). Verified on September 30, 2026. The `/api/v1/skills/search` endpoint returned HTTP 401 in our check. Public search is an external dependency and can change; its adapter is isolated in `api/src/analyze.js`.

Search is live; task classification and ranking are local heuristics (`heuristic-v1`). Ranking uses names, known catalog tags, and popularity only as a tie breaker. It does **not** yet fetch arbitrary `SKILL.md` files, use an LLM reranker, or perform security audits. All results say `not-audited`. Counts are returned only when supplied by the live search.

This version uses a dedicated pre-send shortcut, not interception of another app's Enter key. It copies skill links; it does **not** install skills, change the host model, or automatically send the prompt. Those integrations need one tested host app first. AX support depends on the target app and focused control; rich web editors may require the paste fallback. Cursor and ChatGPT capture still need manual verification on the demo machine.

## Local data flow

The API binds to `127.0.0.1` and rejects browser origins. Raw prompts go only from the native client to this local API. Only controlled topic labels (such as `react performance`) go to skills.sh. No prompt logging, telemetry, persistence, or LLM provider calls. Clicking a skill link opens its public page. Copy actions intentionally replace the clipboard. Do not expose this unauthenticated development API to a network.

The app is locally ad-hoc signed for development, not notarized for distribution. If Accessibility permission stops working after a rebuild, remove and re-add the app in System Settings. Keep running the built `.app` from the same path.

## GitHub / teammate access

The initial repository is private. The owner can add the teammate through GitHub → Settings → Collaborators; their GitHub username is needed. No collaborator has been invited automatically.

If publishing from a fresh machine without an existing remote:

```sh
brew install gh
gh auth login
gh repo create preflight --private --source=. --remote=origin --push
git push -u origin feature/macos-ui feature/backend-intelligence
```

If `origin` already exists, only run `git push -u origin main feature/macos-ui feature/backend-intelligence`.
