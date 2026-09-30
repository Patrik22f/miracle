# Content-index validation — 2026-09-30

This is a local engineering check, not a measured production accuracy claim.

- Backend suite: 120 tests passed, including API payload validation, authentication handling, retained snapshots, bounded concurrency, cache invalidation, selection regressions and Claude hook protocol.
- Swift suite: 42 tests in 6 suites passed, including the new optional knowledge fields, 12-criterion fixture and backward compatibility with responses missing new fields.
- Legacy evaluation: 30/30 controlled cases passed.
- Content evaluation: 28/28 handwritten CZ/EN cases passed.
- `git diff --check`: passed.

## Performance

Measured on this workspace's Mac with its imported library of 186 skills:

| Operation | Samples | Median | P95 | Other |
| --- | ---: | ---: | ---: | --- |
| Warm local selection | 500 | 0.30 ms | 0.60 ms | P99 1.65 ms; cold index preparation 84.05 ms |
| Warm local selection with supplied chat context | 500 | 0.44 ms | 0.67 ms | Synthetic Swift concurrency continuation |
| Claude hook process including Node startup and transcript read | 12 | 145.34 ms | 156.67 ms | Synthetic exact-session transcript; p95 here is the maximum observed value |

The selection measurement excludes disk loading, HTTP and process startup. Hook timing includes loading/compiling the legacy on-disk snapshot and serializing the response. No network or model request occurs in either measurement. Results vary with hardware, library size and content. Run `npm run eval:knowledge` to reproduce the warm index measurement.

Real-library spot checks selected a SwiftUI performance specialist for Czech scrolling optimization, separate SwiftUI accessibility/performance specialists for a combined task, and `stripe-best-practices` for Stripe checkout. Those checks exposed and corrected GRDB misclassification and broad-router displacement. They are not an independent evaluation dataset.

## Context and installed-client verification

- 18 context-focused backend cases cover continuation, effort, active constraints, topic switches, independent chats, malformed history, local HTTP, transcript ancestry, tool/thinking exclusion and bounds. Six new Swift tests cover context transport and lifecycle.
- The previously running server still used `criteria-v2`; it was replaced with the current `knowledge` backend. `/health` confirms `mode: knowledge` and `contextAware: true`.
- Real-library HTTP checks: `Pokračuj` + Swift actor-isolation migration → high / `swift-concurrency-expert`; `Oprav to` + slow SwiftUI rendering → medium / `swiftui-performance-audit`; `Continue` + React performance → medium / `vercel-react-best-practices`; continuation without context → medium provisional / context missing.
- Rebuilt, signed, installed and launched `/Users/patrikfigura/Applications/Preflight.app`.
- Verified the actual native context editor end-to-end: a manually entered Swift migration context with `Pokračuj.` displayed `Using chat context`, `High effort`, `Capable model`, and `swift-concurrency-expert` at 87/100, with demo mode off. Live capture stayed paused during this check.
- Automatic recommendation debounce reduced from 900 ms to 300 ms; native cancellation/lifecycle tests pass.

## Not verified

- Authenticated live skills.sh v1 request: no Vercel OIDC token was available. Tests use documented response fixtures.
- A real Claude Code session loading the generated hook settings; the hook subprocess and protocol were tested directly.
- Automatic conversation-tree capture in live Cursor/Codex windows. Codex UI inspection was unavailable through the computer-use tool; policy and lifecycle tests do not prove compatibility with a real host tree. Manual context is verified.
- Terminal capture before submit, general language understanding, framework-version compatibility or arbitrary dependency availability.
- Precision/recall in production. Use the independent 500-prompt corpus and acceptance targets in the [proposal](SKILL_INTELLIGENCE_PROPOSAL.cs.md) before making such claims.
