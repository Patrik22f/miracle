# Live prompt capture

Current UI: open the review from the menu bar; there is no registered global capture shortcut or separate review window. The capture/selection methods and their historical verification below remain implementation history. Recognized Cursor and Codex prompts now use a 300 ms analysis debounce, and chat context travels with each capture as described in [CHAT_CONTEXT.md](CHAT_CONTEXT.md).

With Accessibility permission and Live capture enabled, Preflight follows the focused editable text field in the foreground application. The overlay stays visible without taking focus on each update. Text is held in memory. Recognized Cursor and Codex prompts can trigger analysis after a 300 ms typing pause when automatic recommendations are enabled. Other fields wait for Analyze in the review popover.

## Components and ownership

| Component | Responsibility |
| --- | --- |
| `PromptCapture.swift` | Sendable source/snapshot/status values and text-size policy. |
| `FocusedTextReader` actor | Synchronous cross-process AX reads, field eligibility, secure-field checks, selection handling and size limits. No UI or network calls. |
| `LivePromptMonitor` on MainActor | Foreground-app selection, trust checks, serial polling, deduplication, lifecycle/cancellation and stale-read rejection. Dependencies can be replaced in tests. |
| `AppModel` on MainActor | Prompt provenance, live/manual/demo transitions and analysis revision checks. Recognized Cursor snapshots can schedule debounced analysis; generic captured fields only change local state. |
| `OverlayView` | Visible capture state, source attribution, permission action and pause/resume. |

Swift 6 checks isolation boundaries. Only Sendable values cross from the reader actor to the UI; AX objects remain inside the reader. The existing API contract is unchanged.

## Timing and lifecycle

- Samples are serial: 350 ms after a readable field; 1 second after a non-input or when Preflight has focus; 2 seconds while permission is missing or the session/display is inactive. These are sampling delays, not guaranteed end-to-end latency.
- Polling is deliberate: third-party editors vary in their support for Accessibility notifications. The service reads only the focused control and at most three ancestors to check secure-field semantics. It never walks windows or whole documents.
- AX messaging has a 150 ms per-element timeout. Reads can take more than one timeout across attributes, but they run off the UI actor and cannot accumulate on every keystroke.
- Permission, foreground app, and lifecycle generation are checked again after an asynchronous read. The reader also verifies that the focused element has not changed. Invalidated reads are discarded.
- Pause/demo/settings cancel text capture; the monitor continues checking permission without reading external fields. Quit stops monitoring. Session/display notifications suppress capture while inactive. An in-flight AX call can finish, but its result is rejected after cancellation.
- Capture pause, automatic-recommendation preference, and display mode are persisted; prompt text is not. Closing the panel leaves menu-bar capture running; pause it in the menu to stop.

## Editing rules

- Live capture uses the full field, preserving whitespace, indentation and newlines. It does not shrink to a selection when the user highlights text.
- A genuinely empty field replaces the old prompt with an empty string. An unreadable field does not masquerade as an empty one.
- Duplicated text/source/field snapshots do not invalidate recommendations. Anchor movement repositions Helpful without reanalyzing. Changed text or a different source does; in-flight analysis is canceled and revision-guarded.
- Typing or pasting in Preflight pauses live capture and removes source attribution. Resuming deliberately lets the next captured field replace the manual draft.
- Demo mode suspends live capture. Leaving demo resumes it only if the live preference is enabled.
- The shortcut captures once before opening the overlay, prefers selected text, and pauses monitoring to protect that excerpt. A failed capture keeps the last snapshot and displays a recovery message.
- In unsupported/secure/unreadable states, a generic manually analyzed snapshot stays labeled “Captured from …”. An automatic Cursor session instead cancels analysis, clears its prompt and recommendations, and removes the Helpful anchor, so stale automatic advice cannot appear for another field.

## Supported surface and limits

The focused element must expose `AXTextField`, `AXTextArea` or `AXComboBox` and either a settable `AXValue` or `AXEditable = true`. Secure text subroles are excluded before any text is read. Value reads use `AXValue`; explicit selected excerpts use `AXSelectedText`. Text is capped at 12,000 UTF-16 code units to match the existing JavaScript API.

On application switches, the reader requests Electron's documented `AXManualAccessibility` mode before reading focus. Electron hosts such as Cursor may otherwise leave their renderer's text tree unavailable. Unsupported applications ignore this attribute; it does not change focus or type into the host.

Native editors and web contenteditable controls can work when they expose these semantics. Custom canvas editors, some Electron controls, and terminal CLI prompts may not. We do not read terminal scrollback, synthesize copy keystrokes, inspect clipboard history, install a keylogger, or guess prompt text from a whole browser page. Host-specific adapters can implement `FocusedTextReading` later without changing prompt state or API contracts.

A source app can provide incomplete or incorrect Accessibility metadata; support must be verified per editor. Password exclusion relies on the metadata the host exposes. Live capture has no AI-app allowlist: any eligible foreground text field is followed while enabled. Automatic analysis has a separate policy: only recognized Cursor prompt labels qualify. Both modes share the same reader, secure-field checks, lifecycle, and size limits.

## Verification

Automated Swift tests cover full-field/selection behavior, whitespace, empty versus missing text, Unicode limits, automatic state updates, deduplication, source changes, manual edits, demo/pause/resume, permission gating/recovery/revocation, self-exclusion, canceled reads, and stale analysis responses. They use deterministic handshakes for races, without sleep-based assumptions or external applications.

The September 30 local verification passed 18 Swift tests and 25 backend tests, built the packaged app, and verified its ad-hoc signature. UI checks verified manual-edit pause, pause persistence across relaunch, missing-permission status, and standard Command-V paste after adding the responder-chain Edit menu. On this machine, macOS labels the Accessibility permission **Device Control and Data Access** and requires system authentication to enable it.

A subsequent compatibility run including the parallel skill-library changes passed 20 Swift tests and 57 backend tests. That source check does not imply that every parallel change is included in the already-running capture build.

The initial UI check observed a snapshot labeled ChatGPT, but did not prove live typing or deletion; the value may have been an empty editor's placeholder. The user subsequently reported capture failing in Codex and Cursor. The running app then showed missing Accessibility permission, and its ad-hoc code hash had changed since the previous authorization. The earlier snapshot must not be treated as a successful host acceptance test.

The build now uses an Apple Development certificate, remembers the selected identity, verifies the signature, and refuses to overwrite a running Preflight process. Signing happens in a temporary directory and the app is installed at `~/Applications/Preflight.app`, outside iCloud-backed Documents. The repository's `build/Preflight.app` is a symlink. Signing in a temporary directory alone was insufficient: File Provider later reattached FinderInfo to the old Documents location and invalidated strict verification. Verification passed after installing outside iCloud, including rejection of a rebuild while the app is running (the executable hash stayed unchanged). The 20 Swift tests also passed after adding Electron activation.

Migration from the old ad-hoc build needs one permission refresh: remove the obsolete Preflight entry, add `~/Applications/Preflight.app`, and enable it. Future builds retain the certificate-backed designated requirement. An explicit `PREFLIGHT_CODESIGN_IDENTITY=-` build still uses a per-binary ad-hoc identity and needs renewed permission after code changes. No TCC database edits or weakened signature requirements are used.

After the user refreshed the permission for the installed build, Preflight recognized it without relaunching. **Cursor 3.22.12, Agents composer** then passed a real foreground test: an unsent draft appeared with Cursor attribution, a second appended edit appeared automatically, and Select All + Delete in Cursor cleared Preflight's field and disabled Analyze. Live capture remained on throughout; no shortcut, clipboard import, or analysis was used. The temporary draft was cleared without sending it. Activating Cursor mattered: automation can type into a background window, which intentionally does not qualify for foreground capture. Codex verification is user-assisted because the computer-use tool cannot interact with its own host app.

**Codex composer:** the user subsequently typed an unsent test prompt and explicitly confirmed “Yes, it mirrors.” This verifies the reported typing issue on their current Codex installation; Codex deletion, selection, and other editor variations were not independently exercised.

Manual acceptance remains necessary for the AX integration:

1. Launch the packaged app, grant Accessibility, and confirm status recovers.
2. In TextEdit, type/paste a multiline sample, edit it, select part of it, and clear it. Confirm full text is mirrored, including clearing, without focus theft.
3. Repeat in Cursor chat, ChatGPT web/desktop, Codex, and the intended browser. Record exact app/version and input tested; do not infer support from another editor in the same app.
4. Switch between fields and apps, then a button/read-only/password field. Confirm provenance and fallback states, and no password capture.
5. Edit manually in Preflight, switch apps, and confirm the draft stays put until Live capture resumes.
6. Start analysis, change external text, and confirm old recommendations never reappear.
7. Pause/resume from panel and menu, toggle demo, revoke/re-grant permission, lock/unlock, close/reopen the panel, and relaunch to verify the saved pause preference.
8. Select an excerpt in a long editable document and use ⌥⌘Return; confirm only the selection is analyzed and capture pauses.

This is a hardened capture foundation, not a claim of enterprise deployment readiness. Signed/notarized distribution, a verified host compatibility matrix, managed app allowlists and per-host adapters remain separate release work.

References: [Apple Accessibility attributes](https://developer.apple.com/documentation/applicationservices/axuielement_h), [AX notifications](https://developer.apple.com/documentation/applicationservices/1462089-axobserveraddnotification), [Electron accessibility activation](https://github.com/electron/electron/blob/main/docs/tutorial/accessibility.md), [Apple code-signing requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).
