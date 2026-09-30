# Miracle / Zázrak

**Model, effort and skills for your next prompt.**

A native macOS prompt companion: write in your AI app and open Miracle from the menu bar to see model, effort and skill recommendations. The prompt preview is a single read-only line. Model and effort are advice; change them in your AI application. Install selected skills together or individually.

Miracle also offers three project-aware next-task prompts through Groq, with cached responses and **Use draft / Copy prompt** actions. Select a project under **Your next task** or **Settings → Prompts**, and configure `GROQ_API_KEY` in the backend `.env`. Selected code excerpts and prompt/chat context go to Groq; [setup and data flow](docs/PROMPT_SUGGESTIONS.md) explain the limits. Claude Code can receive local skill recommendations through its submit hook.

## Start in two minutes

Requirements: macOS 14+, Xcode 16+ / Swift 6, and Node 22+. Local skill matching requires no API key. Optional prompt suggestions require a Groq key.

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

With automatic recommendations enabled, recognized prompt labels trigger analysis after a 300 ms typing pause. The mode menu contains **Stealth** and **Helpful**; its information button explains the selected mode. **Settings** is a separate window, and onboarding appears only on first launch. See [the macOS interface and verification notes](macos/README.md).

Open **Skill library** to browse or refresh imported skills. In recommendations, select skills with the checkboxes and use **Install selected skills**, or install an individual package from its row. Settings chooses installation for this Mac or an explicit project folder. The original prompt stays in the AI app; Miracle does not submit it or change the host's model. See [the import and matching criteria](docs/SKILL_MATCHING.md).

For a presentation, enable **Demo mode** in Settings or choose **Try demo** from the menu bar. The Shopfront website opens in a window that stays open while you type in Cursor. Its source and two prepared prompts are bundled in `macos/Sources/Preflight/Resources/Demo/`. Miracle captures the real coding app's prompt, then shows offline recommendations through Stealth or Helpful. Presentation install actions only change session state. Turn Demo mode off for real analysis. See [presentation details](macos/README.md#presentation-from-a-real-coding-app). The API can also work offline with `SKILLS_MODE=offline npm start`.

## Find the best matching skill

The library supports combined text, availability, source, platform, and purpose filters. Recommendations label the first eligible result **Best match**. The Claude hook identifies it and asks the receiving assistant to mention its name and source. This is the best match under the current ranking in your imported database; an empty result means no skill qualifies.

Query the same database without a server or network access:

```sh
npm run --silent skills:find -- "Fix Swift Sendable actor isolation." --app Codex --provenance installed
```

Use `--scope`, `--purpose`, `--source`, `--q`, and `--limit` to narrow results, or `--json` for automation. Repository agents follow this lookup workflow in [AGENTS.md](AGENTS.md).

The existing official skills.sh connection also supports topic and owner discovery:

```sh
npm run skills:import -- --query "react performance" --owner vercel-labs
```

This needs `VERCEL_OIDC_TOKEN`, supports up to five `--query` flags, filters upstream duplicates, and imports complete content before ranking. Saved queries are reused by **Refresh imports**. Public imports remain capped at 30 skills; prompts used for local analysis never become upstream search terms. See [matching and filtering](docs/SKILL_MATCHING.md) and the [official API documentation](https://skills.sh/docs/api).

## What's working

- Native SwiftUI review, Stealth menu-bar notifications, Helpful prompt-anchored recommendations, first-run onboarding and a dedicated Settings window.
- Automatic capture of supported focused prompt inputs, app detection, secure/read-only field exclusion and a single-line prompt preview.
- Background AX reads, bounded timeouts, serial sampling, permission recovery, stale-read rejection and capture suspension during setup and settings, with local analysis for demo mode.
- `POST /analyze` with request validation, bounded input, timeouts, errors, and stable JSON shapes.
- Content-aware local selection with 12 criteria, versioned profiles, instruction evidence, no prompt-path network, up to eight requested results, and valid abstention.
- Official skills.sh v1 content import with OIDC, bounded allowlisted discovery, four workers, response validation and retained snapshots on failure.
- Claude Code submit hook, manual-invocation controls and local Claude skill imports.
- Installed and public `SKILL.md` imports, a searchable library, explicit provenance, and refresh warnings.
- Explainable prompt criteria, prerequisite checks, abstention, and complementary selection.
- Model capability profile and effort advice; deterministic heuristics keep the demo fast and key-free.
- Shared schemas, example request/response, macOS offline fixture, tests, and CI.


## Shared branch

The backend and macOS UI are integrated on `main`. Both teammates should start new work from the latest `origin/main`; the earlier feature branches are historical work, not separate integration targets. See [setup and handoff notes](docs/BACKEND_HANDOFF.md).

```sh
git fetch origin
git switch main
git pull --ff-only origin main
```

## Repository map

```text
macos/         Swift package: menu bar, focused input, review, model advice, skill installer, API client
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

Request fields: `prompt` (required, 1–12,000 characters), `app` (optional label), `maxSkills` (optional, 0–8). Response: `schemaVersion`, `requestId`, `analysis`, `effort`, `model`, `skills`, `meta`. See [the API guide](docs/API.md) and [response schema](contracts/analyze-response.schema.json).

```sh
npm test                  # offline backend + HTTP + contract checks
npm run skills:import     # installed skills + ten public starter skills
npm run eval              # thirty-prompt relevance report, no network
npm run eval:live         # three legacy public-search checks, requires internet
npm run eval:knowledge    # content-index regression cases and local latency report
npm run --silent claude:config # print a Claude Code hook configuration fragment
npm run macos:test        # build client + decode shared contract in Swift
npm run smoke             # live check against a running API
```

## Public discovery and scope

For the requested enterprise direction, see the [concrete proposal with 12 criteria, alternatives and acceptance targets](docs/SKILL_INTELLIGENCE_PROPOSAL.cs.md). The implementation is a foundation, not a claim of enterprise certification or measured production accuracy.


The legacy discovery adapter uses `https://skills.sh/api/search?q=…&limit=8`, the public endpoint used by the [skills CLI](https://github.com/vercel-labs/skills/blob/main/src/find.ts). Verified on September 30, 2026. The `/api/v1/skills/search` endpoint returned HTTP 401 in our check. Public search is an external dependency and can change; its adapter is isolated in `api/src/analyze.js`.

Default `knowledge` mode selects from the local content index with `knowledge-v1`, 12 criteria and a 70/100 threshold. It never searches the network during analysis. Compiler output is deterministic and evidence-linked; it is not a general semantic model. `hybrid` and `installed` preserve the older `criteria-v2` behavior; `live` and `offline` retain `heuristic-v1`. See [matching criteria](docs/SKILL_MATCHING.md), [the architecture proposal](docs/SKILL_INTELLIGENCE_PROPOSAL.cs.md) and [Claude Code setup](docs/CLAUDE_CODE.md).

The importer supports ten configured public `SKILL.md` starter sources and the official Skills API (`npm run skills:import -- --api`, requiring `VERCEL_OIDC_TOKEN`). `--discover` imports up to 30 allowlisted curated results with complete file bundles. Default local roots include both Codex and Claude Code. Unstudied live search results are excluded from `knowledge` recommendations. The backend does not use an LLM reranker or perform security audits. All results say `not-audited`. Install counts are returned only when supplied by live search.

This version follows the focused editable field through Accessibility; it never intercepts another app's Enter key. Optional installation copies or downloads a complete skill package without running its commands or replacing an existing installation. Model choices are recommendations; the app does not change the host model or send the prompt. AX support depends on the target app and focused control; rich web editors and terminal prompts may not expose supported capture fields. Cursor 3.22.12's Agents composer was verified on this Mac: successive unsent edits appeared automatically and clearing the composer cleared Preflight. The user also confirmed that an unsent prompt typed in Codex mirrors automatically. Other hosts require their own acceptance checks. “Any app” means an app exposing the supported Accessibility text semantics, not universal editor compatibility.

## Local data flow

The API binds to `127.0.0.1` and rejects browser origins. Live capture reads the focused editable field in accessible foreground apps, skipping secure and read-only controls. Captured text stays in memory. Skill analysis in default `knowledge` mode stays on-device; legacy live-discovery modes send controlled topic labels to skills.sh. **Prompt suggestions are a separate optional Groq feature:** bounded source excerpts, relative paths, the project name and current prompt/chat context leave the device. Environment files, common secret files and generated folders are excluded; common credentials are redacted. Only the project folder and preferences persist; no prompt/code logging or telemetry is added. See [the full suggestion data flow](docs/PROMPT_SUGGESTIONS.md). Imported skill snapshots persist in ignored `.preflight/`. Copy actions intentionally replace the clipboard. Do not expose this unauthenticated development API to a network.

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

## Chat-aware recommendations

Short follow-ups now use supplied active-chat context for skills and effort. Claude Code uses its exact-session transcript; the macOS client attempts a bounded read of a labeled conversation around recognized Cursor/Codex composers and offers a reviewable context editor when history is missing. UI capture depends on host accessibility support and remains unverified against live host trees. See [context behavior, privacy and limitations](docs/CHAT_CONTEXT.md).
