# macOS presentation modes

The first launch offers **Stealth** and **Helpful**. The choice and the automatic-recommendations toggle persist in UserDefaults. Settings are available from the mode button in the review UI and by right-clicking the menu-bar icon. The app stays in the menu bar after setup and on subsequent launches.

- **Stealth:** a blue dot signals a new result, including an empty skills list with effort/model advice. An orange dot signals an analysis error. Left-click opens the full review UI in a menu-bar popover and marks the result read.
- **Helpful:** a non-activating panel appears above the focused prompt after analysis. If there is insufficient room above, it moves below and stays inside the current display. It does not take keyboard focus. Review prompt opens the full, keyboard-accessible editor. Dismissing the suggestion lasts until the prompt changes.

## Automatic capture

Cursor is the first supported automatic host (`com.todesktop.230313mzl4w4u92`). Automatic analysis requires a recognized, non-secure Cursor prompt; code editors, search fields and terminals are excluded from automatic analysis. Live capture also mirrors other accessible editable fields into the review window for explicit analysis, including supported Codex controls. Unknown or inaccessible controls keep the manual shortcut/paste fallback.

A single shared `LivePromptMonitor` samples Accessibility serially, waiting 350 ms between readable-field samples (longer when idle or permission is missing). A changed prompt waits another 900 ms before analysis. Editing, clearing the field, leaving the prompt, pausing recommendations or losing permission cancels pending work and invalidates old recommendations. A revision check also rejects late responses from canceled requests. Moving a prompt without editing it repositions the panel without repeating analysis.

Opening Preflight’s review preserves its current prompt. Live capture can continue when focus returns to another app, even with the review window visible. Editing the review pauses Live capture until explicitly resumed; opening settings or entering demo mode suspends text reads. Pausing automatic recommendations alone leaves manual live capture available. `⌥⌘Return` retains explicit selected-text capture; automatic capture uses the complete prompt.

Accessibility permission is requested by the user during setup and may be skipped. The current permission state updates without relaunching. The build script reuses an Apple Development signing identity and installs outside iCloud at `~/Applications/Preflight.app`; `build/Preflight.app` links there. When migrating from an old ad-hoc build, remove its stale Accessibility entry and add the installed app once. Explicit ad-hoc builds still require renewed permission after changes.

Both presentation modes use the imported-skill ranking backend. The full review keeps the Skill library, fit-score explanations, provenance, and selected-skill copy behavior. No prompt text is logged or persisted. `--diagnostics` enables system-log messages for monitor state changes only. The backend contract and data flow are unchanged.

## Validation

From the repository root:

```sh
npm test
npm run macos:test
npm run macos:build
open build/Preflight.app
```

Swift tests cover persisted onboarding choices, recognized/secure/editor fields, debounce, same-text deduplication, field changes, stale responses, cancellation, errors, empty results, dismissal and multi-display placement.

Manual checks:

1. Choose each mode in setup, relaunch and verify the saved choice.
2. Grant Accessibility to the current build, start the API and focus Cursor's Prompt field.
3. Write a React performance prompt without sending it. Verify the mode-specific presentation after the typing pause.
4. Keep typing while Helpful is visible; the host must retain focus and old recommendations must disappear.
5. Open the Stealth popover and verify the dot clears, editing works, and copy includes only selected skills.
6. Clear the prompt, change fields/apps, dismiss Helpful and pause automatic recommendations; verify stale content does not return.
7. Test a greeting, unavailable backend, missing permission, demo mode and an inaccessible control.
8. Check a prompt near display edges and on a secondary display.

Build/test success does not substitute for these host and display checks.

### Integration verification — 2026-09-30

The integration of backend/live capture with the UI branch passed 58 backend tests, 36 Swift tests (including parameterized cancellation/lifecycle cases), 30 controlled relevance scenarios, the signed app build, and the live hybrid API smoke test. The running merged app showed the onboarding and review UI, retained Accessibility permission, and loaded the library with 176 installed and 10 public skills. Automated tests exercise the shared capture-to-recommendation path, geometry-only updates, pause/demo/setup cancellation, and the explicit shortcut while capture is paused.

A fresh foreground Cursor session, physical secondary displays, and VoiceOver remain manual acceptance checks for this merged build. The earlier UI-branch observations below are retained as historical evidence, not a replacement for those checks.

### UI branch verification — 2026-09-30

- Passed: 8 backend tests, 14 Swift tests, app bundle build/ad-hoc signing, `git diff --check` and the live API smoke test.
- Observed in the running app: onboarding rendering, switching/persisting both modes, permission refresh, manual review, packaged demo and live/empty result presentation.
- Observed with Cursor Agents: automatic prompt capture and live Helpful recommendations, continued typing in Cursor while the panel was visible, and updated recommendations for the edited text. The user also confirmed the panel appeared above the prompt. Test-only additions were removed without sending the prompt.
- User-confirmed in Cursor: Stealth's menu-bar notification and opening recommendations work.
- Remaining manual coverage: physical secondary-display placement, VoiceOver navigation and other Cursor input variants. Geometry, unread-state transitions and field exclusion have automated coverage.

The computer-use tool can manipulate a window without making that app the system's foreground application. Automatic monitoring deliberately uses the real foreground application; host checks must account for this when testing.
