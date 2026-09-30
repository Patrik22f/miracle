# macOS app

Preflight lives in the menu bar. Left-click opens the prompt review popover; right-click opens its menu. Launching or reopening an already configured app does not open a separate review window. The global review shortcut is no longer registered. First launch alone presents onboarding.

## Presentation and settings

The review has a display-mode submenu and an adjacent information button. Mode explanations appear on demand.

- **Stealth:** a menu-bar dot signals a new recommendation; orange indicates an analysis error. Opening the review acknowledges the result.
- **Helpful:** a nonactivating panel appears above a recognized Cursor or Codex prompt. It shows the recommended model, supported effort and optional skills while typing remains in Cursor. The panel stays within the current display and can be dismissed for the current prompt.

Settings is a separate window with General, Models and Skills tabs. Onboarding is not reused for settings. The main review and Helpful panel prioritize the prompt and model recommendation. Instructional footers, generic model explanations and raw warning paragraphs have been removed. A short source badge still distinguishes offline results from live search; errors remain visible.

## Models and effort

The captured application's bundle identifier selects Cursor or Codex. The target can also be chosen in the review. Editing a captured prompt keeps its target application. Claude integration is owned by the parallel lane.

The macOS client maps the API's existing `fast`, `balanced` and `capable` profiles onto available models. It does not change the shared API contract or send extra prompt data. This is a recommendation selection, not automation of another application's model picker.

- Cursor models come from a small documented catalog checked on 2026-09-30. Users enable the models available to their account in Settings. Only Grok 4.6 is enabled initially, matching the local account observed during verification. Grok models expose low, medium, high and xhigh when Custom effort is available; otherwise the account uses fixed medium. Models without verified configurable effort have no effort control.
- Codex models are read from `$CODEX_HOME/models_cache.json` or `~/.codex/models_cache.json`. Only listed models and their declared reasoning levels are used. Hidden models are excluded. A missing catalog produces an empty state rather than invented options.

Model selection is heuristic and bounded by the configured catalog. Refresh the Cursor catalog when host capabilities change. Do not infer account access from public model availability.

Supported effort levels appear as a segmented control, with each option directly visible. A model with a fixed effort shows its value as text.

Sources: [Cursor models](https://cursor.com/docs/models), [Grok 4.6 effort](https://cursor.com/docs/models/grok-4-6), [Grok 4.7 effort](https://cursor.com/docs/models/grok-4-7), [Composer 2.5](https://cursor.com/docs/models/cursor-composer-2-5). Codex's installed model cache is the source for the local account.

## Skill installation

Each recommendation and library entry has an install action. Settings chooses This Mac or a project folder. Destinations are `.cursor/skills/<name>` and `.codex/skills/<name>` under the selected root. Project mode requires an explicitly chosen folder before installation. [Cursor's skill directories](https://cursor.com/docs/skills) document its destination; Codex's bundled skill installer documents `.codex/skills`.

Installation copies a complete local skill folder or downloads the matching package from a public GitHub repository. Remote downloads use one immutable tree revision and include scripts, references and assets. No skill commands run during installation. Packages are staged, validated and moved into place only when complete. Existing destinations are never overwritten. Symlinks, invalid paths, mismatched names and oversized packages are rejected. The limits are 300 files and 20 MiB per package, with bounded network requests. Unsupported/private sources produce a recoverable error.

The install state distinguishes progress, success and retryable failure. Library import remains a separate action that indexes skills for recommendations; importing is not installation. Installation does not submit a prompt or claim the host has already reloaded its skills.

## Capture and build

The existing shared live monitor follows accessible text fields; recognized Cursor and Codex prompts trigger analysis after a 300 ms typing pause. Capturing text from Codex selects its model catalog. The shared backend receives the current bounded chat context; the review includes its editor, and Helpful offers Add context when a continuation needs earlier messages. Unsupported fields can be pasted into the review. Live capture defaults to on. Editing the prompt or chat context inside Preflight pauses it for that session without persisting an off preference; an explicit toggle remains a saved user choice. Settings and demo mode suspend external text reads. Prompt text remains in memory.

Build with `npm run macos:build` after quitting Preflight. The build reuses an Apple Development signing identity, installs at `~/Applications/Preflight.app`, and links `build/Preflight.app` there. Accessibility may need a one-time refresh when migrating from an ad-hoc build. `--diagnostics` logs capture state only.

## Verification

Run `npm test`, `npm run macos:test` and `git diff --check`. To run the optional real GitHub installation check into a disposable temporary folder:

```sh
PREFLIGHT_INSTALL_SMOKE=1 swift test --package-path macos --build-system native --filter SkillInstallationTests
```

Tests cover existing capture/cancellation, model profile mapping, account availability, model-specific effort, Codex cache filtering, persisted installation destinations, complete local and remote packages, path rejection, symlinks, refusal to overwrite and cleanup after failure. The live installation check verifies the React skill and its supporting rules.

Local verification on 2026-09-30: 58 backend tests and 46 regular Swift tests passed; the optional live GitHub installation also passed separately. The signed app bundle built successfully and passed strict signature verification. No skill was installed into a real user or project skill directory during automated verification; installation tests used disposable folders.

The running signed build was checked through its menu-bar popover: the mode information wraps fully, the review has an opaque system background, and a live React-task analysis shows the model above three skill installation actions. Switching Cursor to Codex updates the model, supported effort levels and installation target. The dedicated Settings window and its model list were also inspected. Install completion and failure were verified by automated package tests, not by modifying the user's skill directories. The final effort menu was replaced with a native segmented control; the Live launch preference has a regression test.

Manual checks for each new build: menu-bar-only opening; dedicated settings versus first-run onboarding; mode submenu and information popover; model and effort menus for both target apps; install progress/error/success; keyboard copy and paste; no focus theft while Helpful appears. Physical secondary displays and VoiceOver still require separate acceptance testing.

Integration with the context-aware backend passed 120 backend tests and 53 Swift tests. The merge retains missing/partial-context feedback and manual context editing alongside the new menu-bar presentation.
