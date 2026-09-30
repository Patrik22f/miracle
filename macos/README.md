# Miracle for macOS

Miracle lives in the menu bar. Left-click opens the prompt review popover; right-click opens its menu. Launching or reopening an already configured app does not open a separate review window. The review stays open when switching to another app; close it with its × button or the menu-bar icon. The global review shortcut is no longer registered. First launch alone presents onboarding.

## Presentation and settings

The mode menu contains only Stealth and Helpful. An adjacent information button shows the selected mode's explanation on demand.

- **Stealth:** a menu-bar dot signals a new recommendation; orange indicates an analysis error. Opening the review acknowledges the result.
- **Helpful:** a nonactivating panel appears above the recognized AI prompt. It shows the recommended model, supported effort and optional skills while typing remains in the host app. The panel stays within the current display and can be dismissed for the current prompt.

Settings is a separate window with General, Prompts, Models and Skills tabs. Onboarding is not reused for settings. The main review and Helpful panel prioritize the prompt and model recommendation. Instructional footers, generic model explanations and raw warning paragraphs have been removed. A short source badge still distinguishes offline results from live search; errors remain visible.

**Settings → General → Show onboarding again** reopens the welcome and permission setup without resetting preferences. Capture pauses while the welcome window is open and resumes when it is completed or closed.

The review shows only a single line from the beginning of the captured prompt, truncated with an ellipsis. It is plain read-only text without an input background or separate heading. Users compose their prompt in the AI application. The full captured text is still used for analysis. Captured prompts remain read-only. **Your next task** adds project-aware suggestions and Copy prompt. **Use draft** or editing chat context pauses capture for the session and reveals **Review draft**, where the draft can be edited, copied, or replaced by resuming live capture. The host comes from the captured app; there is no host-app picker.

## Models and effort

The captured application's bundle identifier automatically selects Cursor or Codex for recommendations and installation. Unsupported applications do not inherit the previous host's installation target. Claude Code uses the backend submit hook described in [CLAUDE_CODE.md](../docs/CLAUDE_CODE.md).

The macOS client maps the API's existing `fast`, `balanced` and `capable` profiles onto available models. Requests include the bounded prompt and available chat context; optional Groq suggestions also use sampled project excerpts. Model and effort are read-only recommendations. Users change them in their AI application; Miracle exposes no model or effort picker.

- Cursor models are read from its local `User/globalStorage/state.vscdb` in read-only mode. Only model catalog fields and enabled/disabled overrides are extracted. Effort options come from each model’s declared parameters. Settings offers a manual fallback if Cursor’s private storage format changes. Detected settings reflect local configuration, not a guarantee of account quota or server-side access.
- Codex models are read from `$CODEX_HOME/models_cache.json` or `~/.codex/models_cache.json`. Hidden models are excluded; declared effort options are preserved. A missing catalog produces an empty state.
- Catalogs refresh on launch, after 30 seconds during active use, or with **Refresh models**. No model catalog or prompt is sent to a remote service.

Selection first matches task capability (`fast`, `balanced`, `capable`), then effort support, then host catalog order. When a tier is missing, the nearest available tier is selected. Effort maps to the nearest supported level, preferring more reasoning on ties. Names and local descriptions supply heuristic capability tiers; they are not benchmark scores. The review explains both task effort and model selection, including when only one model is enabled.

The recommended supported effort appears as plain text. There are no dropdowns, segments, selection states or disabled input controls in the recommendation card.

Cursor’s local storage is an undocumented adapter with fixture and opt-in live tests. Public model context: [Cursor models](https://cursor.com/docs/models-and-pricing). The local catalogs are authoritative for the choices displayed on this Mac.

## Skill installation

Each recommendation and library entry has an install action. Settings chooses This Mac or a project folder. Destinations are `.cursor/skills/<name>` and `.codex/skills/<name>` under the selected root. Project mode requires an explicitly chosen folder before installation. [Cursor's skill directories](https://cursor.com/docs/skills) document its destination; Codex's bundled skill installer documents `.codex/skills`.

The main review and Helpful panel also offer **Install selected skills**. Checkboxes select the packages; installed packages are skipped and repeated clicks reuse pending installs. A failure is shown on its own row without stopping other selected installations. Retrying processes the remaining packages. GitHub rate-limit failures include the reset time when available.

Installation copies a complete local skill folder or downloads the matching package from a public GitHub repository. Remote downloads use one immutable tree revision and include scripts, references and assets. No skill commands run during installation. Packages are staged, validated and moved into place only when complete. Existing destinations are never overwritten. Symlinks, invalid paths, mismatched names and oversized packages are rejected. The limits are 300 files and 20 MiB per package, with bounded network requests. Unsupported/private sources produce a recoverable error.

The install state distinguishes progress, success and retryable failure. Library import remains a separate action that indexes skills for recommendations; importing is not installation. Installation does not submit a prompt or claim the host has already reloaded its skills.

## Presentation from a real coding app

Enable **Settings → General → Demo mode** to open the Shopfront website. Its normal resizable window stays open when switching to Cursor. The website contains no AI chat: write the presentation prompts in Cursor's actual prompt field. Miracle captures them through its normal Accessibility path, detects the host and shows recommendations through the real Stealth menu-bar review or Helpful panel above Cursor's input. Accessibility permission and automatic recommendations must be enabled.

The source is in `Sources/Preflight/Resources/Demo/`; it is a standalone HTML/CSS/JavaScript storefront with no database or AI service. Open this folder in Cursor to use it as the example project. `README.md` in that folder contains both exact Czech prompts:

1. Add a database for products, customers and orders → `supabase-postgres-best-practices`.
2. Redesign like Apple.com, improve marketing copy and build a SwiftUI iOS app → `frontend-design`, `copywriting`, `swiftui-expert-skill`.

While Demo mode is on, captured prompts use a small local keyword matcher and these four curated entries instead of the backend. Model and effort use the detected host's catalog, with the full bundled Cursor catalog available for presentation. Individual and selected install actions affect only in-memory demo state. The skill library searches the same offline entries. Neither analysis nor these install actions require network access. At the user's request no simulation labels appear in the presentation interface; Demo mode remains explicit in Settings. Turning it off closes Shopfront, clears its result and install state, and returns analysis to the normal API.

Public skill references: [Supabase](https://github.com/supabase/agent-skills), [frontend-design](https://github.com/anthropics/skills/tree/main/skills/frontend-design), [copywriting](https://github.com/coreyhaines31/marketingskills/tree/main/skills/copywriting), [SwiftUI Expert](https://github.com/avdlee/swiftui-agent-skill).

The web view only loads bundled files in a nonpersistent store, with remote navigation and network requests blocked. It has no bridge to the prompt model. Tests cover both scenarios, real-host capture data, no API calls in demo, stale-result rejection, return to normal analysis, isolated installation state and resource packaging.

## Capture and build

The shared live monitor follows accessible text fields. The review includes a chat-context editor and optional project-aware suggestions; [PROMPT_SUGGESTIONS.md](../docs/PROMPT_SUGGESTIONS.md) describes their setup and data flow. Recognized Cursor and Codex prompt labels trigger analysis after the typing pause; search, code editor and secure fields are excluded from automatic analysis. An unrecognized host field can be reanalyzed from the preview's refresh action. Live capture starts on, with no visible toggle; the obsolete saved-off preference is cleared during initialization. Settings suspends external text reads; demo keeps the same live capture path and substitutes local recommendations. Prompt text remains in memory.

Build with `npm run macos:build` after quitting Miracle (or its previous Preflight build). The build reuses an Apple Development signing identity, installs at `~/Applications/Miracle.app`, and links `build/Miracle.app` there. The previous default Preflight installation is migrated only after the new bundle has been signed and verified. `build/Preflight.app` remains a compatibility symlink. The bundle identifier and internal Swift module stay unchanged to retain preferences and signing identity; the visible app and executable are named Miracle. `MIRACLE_APP_PATH` and `MIRACLE_CODESIGN_IDENTITY` accept custom values, with the previous `PREFLIGHT_` variables retained as aliases. Accessibility may need a one-time refresh when migrating from an ad-hoc build. `--diagnostics` logs capture state only.

## Verification

The integrated `main` build passed 148 backend tests and 78 Swift tests. A separately signed test bundle launched successfully; onboarding, prompt settings, model catalogs and Shopfront resources were checked. The regular installation build was left untouched because an older app was running. See [the current handoff](../docs/BACKEND_HANDOFF.md) for checks and remaining acceptance work. The records below describe earlier UI builds.

Run `npm test`, `npm run macos:test` and `git diff --check`. To run the optional real GitHub installation check into a disposable temporary folder:

```sh
PREFLIGHT_INSTALL_SMOKE=1 swift test --package-path macos --build-system native --filter SkillInstallationTests
```

Tests cover existing capture/cancellation, model profile mapping, account availability, model-specific effort, Codex cache filtering, persisted installation destinations, complete local and remote packages, path rejection, symlinks, refusal to overwrite and cleanup after failure. The live installation check verifies the React skill and its supporting rules.

Local verification on 2026-09-30: 58 backend tests and 54 regular Swift tests passed; the optional live GitHub installation passed separately before GitHub's unauthenticated API quota was exhausted. The signed app bundle built successfully and passed strict signature verification. No skill was installed into a real user or project skill directory during automated verification; installation tests used disposable folders.

Automated coverage includes automatic Cursor/Codex target changes, migration of the old Live preference, selected-only installation, retries, existing-package preservation and partial failure. Previous signed-build UI checks covered the separate Settings window, readable mode information, model and effort options, and individual installation actions. Codex UI automation is unavailable in this environment, so its live prompt-label detection still needs acceptance testing in the host app.

The Miracle build was launched after migrating the default Preflight installation. Its renamed review and Settings window, new monogram and preserved Accessibility permission were checked in the running app. Bundle metadata, icon packaging, demo resource, both build symlinks and retained onboarding preference were verified. A manual reanalysis in the review showed the recommended model and effort as text, with no selectors in either the rendered card or Accessibility tree. Both presentation modes use this shared recommendation view. This check does not establish automatic prompt capture in Codex.

The presentation build was checked with both Czech prompts typed into the real Cursor input without sending them. Miracle captured the prompts and showed Supabase for the first, then frontend-design, copywriting and SwiftUI Expert for the second. Individual and selected presentation installation states were verified. The review stayed open across app switches, and the separate Shopfront window remained available when Cursor regained focus. The user also confirmed that Helpful displayed all three skills above the real Cursor input after editing the second prompt.

Manual checks for each new build: menu-bar-only opening; dedicated settings versus first-run onboarding; exactly two mode options; read-only prompt preview; automatic host detection; read-only model and effort advice; selected and individual installation; no focus theft while Helpful appears. Physical secondary displays and VoiceOver still require separate acceptance testing.

## Brand artwork

Miracle uses a custom rounded m monogram. `Sources/Preflight/MiracleArtwork.swift` defines the shared vector geometry for the monochrome menu-bar template and interface mark. `Branding/main.swift` renders the same shape in white on a blue app-icon tile; the build produces the complete `.icns` size set. No external image service or font is required.
