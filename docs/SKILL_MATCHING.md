# Content-aware skill matching

Default `knowledge` mode recommends from an imported, versioned local library. No search or LLM request runs on the prompt path. Unknown skills with metadata alone are ineligible. See [the Czech architecture proposal and 12 criteria](SKILL_INTELLIGENCE_PROPOSAL.cs.md) and [Claude Code setup](CLAUDE_CODE.md).

## Import and study

```sh
npm run skills:import                    # local roots + bounded public starter sources
npm run skills:import -- --local-only    # local roots only
npm run skills:import -- --api           # official Skills API details; Vercel OIDC required
npm run skills:import -- --discover      # curated discovery from allowed sources, max 30
```

Local roots include Codex skills and its plugin cache (respecting `CODEX_HOME`), Cursor skills, built-in skills and plugins, `~/.agents/skills`, and Claude skills. Repeated CLI `--root` replaces the import roots. The running default server adds standard local roots and scans on first use and at most once per minute; public snapshots are retained without network access. Refresh reuses saved roots and provider. Import never follows nested symlinks, executes a skill or installs dependencies. Local SKILL.md files are capped at 256 KiB, traversal at eight levels and 2,000 files. The public starter provider uses ten explicitly configured GitHub URLs. With a Vercel OIDC token, the default public provider is the official skills.sh v1 API. Explicit `--api` never silently falls back to unauthenticated search.

The official provider fetches stable IDs and complete file trees from documented endpoints, validates identities and relative paths, limits each response to 2 MiB/256 files, rejects redirects and uses four workers. An injected token provider is called per request; CLI usage reads `VERCEL_OIDC_TOKEN`. A deployment should supply a rotating token provider. Credentials never enter snapshots or warnings. Failures retain prior versions with warnings. Discovery is source-allowlisted and happens during import, never from private prompt terms. Well-known/domain sources are not yet supported by this adapter.

Each imported record has content, SHA-256, provenance, import time, optional API file bundle and a serializable `study` profile. The compiler extracts operations, scopes, purposes, instruction lines, simple exclusions, recognized agent extensions (a `context: fork` hint alone does not make portable instructions Claude-only) and referenced paths. It does not execute instructions or allow them to change weights. Reused studies must match compiler version and content hash. Older libraries compile once when loaded.

This deterministic compiler is not general semantic understanding. Scope/purpose rules and selected workflow prerequisites remain curated. Supporting API files are stored and checked for references, but are not yet semantically studied. Locally linked dependencies and installed CLI/MCP availability are not verified. All results remain `not-audited`.

## Runtime

A cached snapshot and inverted indexes retrieve candidates by scope, purpose, description terms or exact name. Separate term postings retrieve evidence lines without repeatedly parsing whole bodies. HTTP requests share a single in-flight snapshot load. Atomic file replacement invalidates the cache on the next check (at most one second). Invalid replacements retain the last valid snapshot with a warning. Changed local SKILL.md files are picked up by the automatic local refresh; only imported snapshots are scored.

The selector checks scope, purpose, provider prerequisites, prompt exclusions, content hash, qualified body exclusions, agent compatibility, invocation flags and known missing API references. It requires body evidence for automatic selection. Then it scores 12 independent components totaling 100: purpose 18, framework/platform 15, operation 10, output artifact 7, description evidence 10, instruction evidence 12, workflow prerequisites 5, negative constraints 5, agent compatibility 5, availability 5, snapshot freshness 3, specialization 5.

The threshold is 70. Explicit requests come first, then precise platform fit, then score, installed availability and stable ID. Scope precedence prevents a broad Apple router displacing a SwiftUI specialist simply through more repeated terms. Popularity supplies no relevance. The native app requests up to six distinct names; the API defaults to three and accepts zero through eight. Distinct names are selected, and additional results must cover a new purpose/platform pair unless explicitly requested. No skill is a valid result.

Responses expose the 12 component scores and optional `knowledge` with compiler version, hash, evidence line numbers and reference counts. They do not expose full bodies. `confidence` is score/100 for wire compatibility, not a calibrated probability. Simple CZ vocabulary is supported; complex negation and unrestricted natural language remain limitations.

## Evaluation

`npm test` covers API identity/size/path validation, outages, cache replacement, protocol behavior, compatibility, explicit invocation and ranking regressions. `npm run eval:knowledge` runs 28 handwritten scenarios and 500 warm selections, separating cold compilation from warm p50/p95/p99. Measurements exclude HTTP, model inference and hook process startup. The scenarios are regression fixtures, not production accuracy estimates. The proposal defines a separate human-labeled evaluation and target metrics before any enterprise accuracy claim.

Legacy `hybrid`/`installed` modes preserve `criteria-v2` and its 60-point threshold. `hybrid` still does live public discovery; use `knowledge` for the new content-only recommendation guarantee. `live`/`offline` retain the old `heuristic-v1` path for compatibility and demonstrations.

## Topic search and filters

The existing skills.sh adapter supports the [official `/api/v1/skills/search` endpoint](https://skills.sh/docs/api):

```sh
npm run skills:import -- --query "react performance" --owner vercel-labs
```

A Vercel OIDC token is required. Up to five queries of 2–200 characters are allowed. The optional owner is a GitHub owner. Explicit topic searches can find repositories outside the curated allowlist; duplicates, malformed identities, and results outside a requested owner are excluded. Search returns candidate IDs only; content retrieval and study must succeed before recommendation. Seeds, topic results, and extra curated discovery share a 30-skill limit, in that priority order. Failed searches retain previous candidates within the limit; failed detail fetches retain their exact prior snapshots. Saved queries and owner survive app refresh and automatic local scans. Running the import CLI again replaces the configuration with its new flags.

`GET /skills` accepts `q`, `provenance`, `source`, `scope`, and `purpose`. Search terms match metadata in any order; all supplied fields must match. The native library offers those filter categories, a result count, and a clear-filters action. Library filters affect browsing only.

`POST /analyze` accepts the same fields inside `filters`. Filtering happens before ranking, limiting, and complementary selection, allowing the next eligible candidate to win when the first is filtered out. Content evidence, score threshold, agent compatibility, exclusions, and user opt-outs still apply. The ranking prioritizes explicit requests, precise platform fit, score, installed availability, then stable ID; it does not measure global skill quality. `meta.bestSkillId` identifies the first result, or is null when none qualifies or `maxSkills` is zero.

```sh
npm run --silent skills:find -- "Fix Swift Sendable actor isolation." --app Codex --provenance installed
npm run --silent skills:find -- "Optimize slow React rendering." --scope react --json
```

The local CLI uses the same content ranker and prints **Best match**, source, score, and evidence without a server. `--json` returns the analysis contract. The app labels the winner and includes the request to mention its name/source in copied prompts only when that skill remains selected. The Claude hook marks exactly one record with `bestMatch: true` and asks the assistant to mention it. No result is manufactured for an unrelated task. Imported snapshots are not the complete skills.sh catalog.
