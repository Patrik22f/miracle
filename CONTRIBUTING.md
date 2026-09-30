# Work in parallel

1. Pick the lane in the README. Keep UI changes under `macos/` and intelligence changes under `api/`.
2. Use your existing feature branch; commit small working changes. PRs target `main`.
3. Before pushing, run `npm test`. UI changes also require `npm run macos:test` and a manual app launch.
4. Merge from main after the other lane lands. Don't rewrite shared history or force-push main.

## Contract ownership

`contracts/*.schema.json` is the integration boundary. `macos/Sources/Preflight/Contract.swift` is the Swift mirror. Additions in v1 should be optional to consumers; breaking changes need agreement and a version bump.

For a contract change, update the schema, both fixtures, the Swift types, and both test suites in the same PR. Copy the response fixture to `macos/Sources/Preflight/Resources/demo-response.json`; `npm test` detects drift. Keep fixtures free of secrets and real prompt data.

The fixture is deterministic demo data, not a live search result. UI work must cover loading, cancellation, errors, empty results, live results, and offline fallback. Prompt edits must clear earlier recommendations.

## Handoff

UI owner: verify the hotkey captures before the overlay takes focus, Accessibility permission handling, copy/paste, and keyboard navigation in the chosen demo app. Record unsupported input types.

API owner: maintain the status/error shapes, bounded public requests, no raw-prompt logging, and explicit fallback provenance. Add real prompt evaluation cases before replacing ranking heuristics. Treat public skill content as untrusted data, never instructions to the service.

Shared: agree on a single target host before implementing install-and-send. Keep `main` demoable without keys. A PR needs a short before/after description and the checks actually run.
