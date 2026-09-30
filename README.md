# Preflight

**The right Agent Skills, before you send.**

A native macOS prompt companion: type in a supported app and see the focused field appear automatically in **Your prompt**. Choose **Analyze prompt** to review installed and public skill recommendations. Skills are the product; model and effort are secondary advice.

## Start in two minutes

Requirements: macOS 14+, Xcode 16+ / Swift 6, and Node 22+. No npm packages, API keys, database, or paid services are required.

```sh
cp .env.example .env
npm run skills:import
npm start
```

In a second terminal, from the same repo:

```sh
npm run macos:build
open build/Preflight.app
```

The sparkle menu-bar item opens the overlay. Click **Enable Accessibility…**, allow **Preflight** in System Settings → Privacy & Security → Accessibility, and leave **Live capture** on. Focus an editable prompt field in another app and type: its full text follows into **Your prompt**, including edits and deletions. The panel stays visible while you work in the other app. Capture recovers after permission is granted without relaunching.

On macOS versions that label this permission **Device Control and Data Access**, use that section under Privacy & Security. macOS may require Touch ID or your account password to approve it.

With **Recommend automatically as I write** enabled, recognized Cursor prompts are analyzed after a 900 ms typing pause. Other captured fields wait for **Analyze prompt**; the shortcut also analyzes explicitly. Pausing automatic recommendations keeps text capture available. Editing or pasting inside Preflight pauses Live capture so your draft is protected; switch **Live capture** back on to resume. Setup and demo mode suspend capture. Preferences are saved, but prompt text is not. See [presentation modes](macos/README.md).

**⌥⌘Return** still captures and analyzes a one-time snapshot, preferring selected text. It pauses live capture to preserve your selected excerpt. If a host does not expose an editable Accessibility field, copy and paste into Preflight instead. See [capture architecture and the host verification checklist](docs/LIVE_CAPTURE.md).

Open **Skill library** to browse or refresh imported installed and public skills. Expand **Why this skill** to inspect the fit score. Matching checks purpose, platform/artifact, prerequisites, description evidence, and available instructions. It returns up to three complementary skills scoring at least 60/100. See [the import and matching criteria](docs/SKILL_MATCHING.md).

Review the skills, select the ones you want, and click **Copy with skills**. Paste back into your AI app, review, and send. Closing the overlay leaves the original input untouched.

For a UI-only demo, no backend is needed:

```sh
open build/Preflight.app --args --demo
```

Or choose **Try demo** from the menu bar. Demo mode always shows the clearly labeled sample response, regardless of the text. Turn Demo mode off for real analysis. The API can also work offline with `SKILLS_MODE=offline npm start`.

## What's working

- Native SwiftUI review, Stealth menu-bar notifications, Helpful prompt-anchored recommendations, onboarding, and a dedicated registered global shortcut.
- Automatic capture of supported focused editable text inputs, app provenance, persistent pause/resume, secure/read-only field exclusion, and paste fallback.
- Background AX reads, bounded timeouts, serial sampling, permission recovery, stale-read rejection, and automatic pause for manual editing and demo mode.
- `POST /analyze` with request validation, bounded input, timeouts, errors, and stable JSON shapes.
- Public skills.sh search, normalization, deduplication, relevance ranking, up to three results, and a valid “no skill needed” result.
- Installed and public `SKILL.md` imports, a searchable library, explicit provenance, and refresh warnings.
- Explainable prompt criteria, prerequisite checks, abstention, and complementary selection.
- Model capability profile and effort advice; deterministic heuristics keep the demo fast and key-free.
- Shared schemas, example request/response, macOS offline fixture, tests, and CI.

## Two people, two lanes

| Owner | Paths | Branch | First milestone |
| --- | --- | --- | --- |
| UI/macOS teammate | `macos/`, `scripts/build-macos.sh` | `feature/macos-ui` | Verify capture in Cursor, polish overlay and permission onboarding |
| Backend/intelligence teammate | `api/`, `scripts/`, `.env.example` | `feature/backend-intelligence` | Extend the relevance evaluation; add content-aware reranking |
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
api/eval/      Public-search and imported-skill prompt evaluation cases
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
npm run skills:import     # installed skills + ten public starter skills
npm run eval              # thirty-prompt relevance report, no network
npm run eval:live         # three public-search checks, requires internet
npm run macos:test        # build client + decode shared contract in Swift
npm run smoke             # live check against a running API
```

## Public discovery and scope

The adapter uses `https://skills.sh/api/search?q=…&limit=8`, the public endpoint used by the [skills CLI](https://github.com/vercel-labs/skills/blob/main/src/find.ts). Verified on September 30, 2026. The `/api/v1/skills/search` endpoint returned HTTP 401 in our check. Public search is an external dependency and can change; its adapter is isolated in `api/src/analyze.js`.

Default `hybrid` mode combines imported skills and live discovery using explainable local ranking (`criteria-v2`). Purpose and compatible platform are eligibility requirements. Imported descriptions, reviewed annotations, and workflow prerequisites supply evidence. `SKILLS_MODE=installed` uses only installed imports without network access during analysis. Older `live` and `offline` modes retain `heuristic-v1`. See [matching criteria](docs/SKILL_MATCHING.md) and [the relevance evaluation](docs/RELEVANCE.md).

The importer fetches ten configured public `SKILL.md` sources; arbitrary live results remain metadata-only. The backend does not use an LLM reranker or perform security audits. All results say `not-audited`. Install counts are returned only when supplied by live search.

This version follows the focused editable field through Accessibility and keeps a dedicated pre-send shortcut; it never intercepts another app's Enter key. It copies skill paths and links; it does **not** install skill dependencies, change the host model, or automatically send the prompt. AX support depends on the target app and focused control; rich web editors and terminal prompts may require paste. Cursor 3.22.12's Agents composer was verified on this Mac: successive unsent edits appeared automatically and clearing the composer cleared Preflight. The user also confirmed that an unsent prompt typed in Codex mirrors automatically. Other hosts require their own acceptance checks. “Any app” means an app exposing the supported Accessibility text semantics, not universal editor compatibility.

## Local data flow

The API binds to `127.0.0.1` and rejects browser origins. Live capture reads the focused editable field in any accessible foreground app, not just AI apps. It skips Preflight itself, secure fields identified by Accessibility, and read-only controls. Captured text stays in memory. Analysis is explicit except for recognized Cursor prompts when automatic recommendations are enabled. Raw prompts go only from the native client to this local API during analysis. Only controlled topic labels (such as `react performance`) go to skills.sh. No prompt logging, telemetry, prompt persistence, or LLM provider calls. Imported skill snapshots persist only in the ignored local `.preflight/` directory. Clicking a skill link opens its local instructions or public source. Copy actions intentionally replace the clipboard. Do not expose this unauthenticated development API to a network.

Quit Preflight before rebuilding; the build script refuses to overwrite a running app. It automatically selects a single available Apple Development certificate and remembers that identity locally in `build/.signing-identity`. With multiple certificates, set `PREFLIGHT_CODESIGN_IDENTITY` to the desired name or SHA-1. Builds are signed in a temporary directory, then installed at `~/Applications/Preflight.app` and verified. The `build/Preflight.app` path is a symlink to that installation. Both signing and the runnable bundle stay outside iCloud storage, which can invalidate signatures by reattaching Finder metadata. Set `PREFLIGHT_APP_PATH` to another absolute, non-iCloud `.app` path if needed. This is development signing, not notarized distribution.

If migrating from an older ad-hoc build, remove its Preflight entry in System Settings, add `~/Applications/Preflight.app`, and enable it once. Subsequent builds use the same certificate identity so the permission can survive updates. Keep running the `.app` from the same path. `PREFLIGHT_CODESIGN_IDENTITY=-` explicitly requests a disposable ad-hoc build, whose permission must be renewed after code changes.

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
