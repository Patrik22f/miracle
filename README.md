# Miracle

**Model, effort and skills for your next prompt.**

A native macOS prompt companion: write in your AI app and open Miracle from the menu bar to see model, effort and skill recommendations. The prompt preview is a single read-only line. Model and effort are advice; change them in your AI application. Install selected skills together or individually.

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
open build/Miracle.app
```

The m-shaped menu-bar icon opens Miracle. Allow **Miracle** in System Settings → Privacy & Security → Accessibility, then focus the prompt in Cursor or Codex. Live capture starts enabled. The captured application determines the model catalog and installation destination automatically.

On macOS versions that label this permission **Device Control and Data Access**, use that section under Privacy & Security. macOS may require Touch ID or your account password to approve it.

With automatic recommendations enabled, recognized prompt labels trigger analysis after a 900 ms typing pause. The mode menu contains **Stealth** and **Helpful**; its information button explains the selected mode. **Settings** is a separate window, and onboarding appears only on first launch. See [the macOS interface and verification notes](macos/README.md).

Open **Skill library** to browse or refresh imported skills. In recommendations, select skills with the checkboxes and use **Install selected skills**, or install an individual package from its row. Settings chooses installation for this Mac or an explicit project folder. The original prompt stays in the AI app; Miracle does not submit it or change the host's model. See [the import and matching criteria](docs/SKILL_MATCHING.md).

For a UI-only demo, choose **Try demo** from the menu bar. Demo mode uses the bundled response and needs no backend. Turn Demo mode off for real analysis. The API can also work offline with `SKILLS_MODE=offline npm start`.

## What's working

- Native SwiftUI review, Stealth menu-bar notifications, Helpful prompt-anchored recommendations, first-run onboarding and a dedicated Settings window.
- Automatic capture of supported focused prompt inputs, app detection, secure/read-only field exclusion and a single-line prompt preview.
- Background AX reads, bounded timeouts, serial sampling, permission recovery, stale-read rejection and capture suspension during setup, settings and demo mode.
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
macos/         Swift package: menu bar, focused input, recommendations, settings, API client
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

Miracle follows accessible prompt fields without intercepting another application's Enter key. It can install skill packages; it does not execute their commands, install dependencies, change the host model or send the prompt. AX support depends on the host app and focused control. Cursor prompt capture was verified locally; Codex live prompt-label detection still needs acceptance testing in the host app. See [verification details](macos/README.md).

## Local data flow

The API binds to `127.0.0.1` and rejects browser origins. Live capture reads the focused editable field in any accessible foreground app, not just AI apps. It skips Miracle itself, secure fields identified by Accessibility, and read-only controls. Captured text stays in memory. Analysis is explicit except for recognized Cursor and Codex prompts when automatic recommendations are enabled. Raw prompts go only from the native client to this local API during analysis. Only controlled topic labels (such as `react performance`) go to skills.sh. No prompt logging, telemetry, prompt persistence, or LLM provider calls. Imported skill snapshots persist only in the ignored local `.preflight/` directory. Clicking a skill link opens its local instructions or public source. Do not expose this unauthenticated development API to a network.

Quit Miracle before rebuilding; the build also detects a running older Preflight executable. Builds reuse the locally selected Apple Development signing identity, generate the app icon, sign outside iCloud storage, and install at `~/Applications/Miracle.app`. The previous default Preflight installation migrates only after successful signing and verification. `build/Miracle.app` points to the installation; `build/Preflight.app` remains a compatibility shortcut.

Use `MIRACLE_APP_PATH` for another absolute app path and `MIRACLE_CODESIGN_IDENTITY` for an explicit certificate. The former `PREFLIGHT_` variables remain compatible. The bundle identifier, internal Swift module and local data directories keep their existing names to preserve settings and integration compatibility. This is development signing, not notarized distribution. See [build and permission notes](macos/README.md).

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
