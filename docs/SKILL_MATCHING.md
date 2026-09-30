# Skill import and prompt matching

Preflight imports installed `SKILL.md` files and a public starter collection. Default `hybrid` mode evaluates that library and searches skills.sh using controlled topic labels. The **Skill library** sheet lets you search imports, inspect their scopes and purposes, open the original instructions, and refresh the import.

## Import

```sh
npm run skills:import
npm start
```

The default local root is `~/.codex/skills`, including `.system`. Ten public sources are declared in `api/src/skill-library.js`: Vercel React performance and web guidelines, Superpowers debugging and TDD, Supabase Postgres guidance, and Anthropic frontend design, PDF, Word, spreadsheets, and presentations. This is a starter collection, not a mirror of skills.sh. Other public results are discovered on demand; their instruction bodies are not downloaded.

Add active plugin folders or another collection explicitly:

```sh
npm run skills:import -- --root "$HOME/.codex/skills" --root /absolute/path/to/plugin/skills
```

Repeated `--root` arguments replace the default root. **Refresh imports** reuses the saved roots. `--local-only` omits public downloads; `SKILLS_MODE=installed npm start` also disables public discovery during analysis.

The machine-local `.preflight/skills.json` stores names, descriptions, bounded `SKILL.md` bodies, original locations, SHA-256 digests, and import times. It is excluded from Git and created with owner-only permissions. Bodies never execute and never enter HTTP responses. Local links point to the original file so sibling references remain available. Public links point to the original GitHub file. Supporting files are not copied; import does not install dependencies or grant tool access.

Limits: 256 KiB per file, 2,000 local files, eight directory levels, and six seconds per configured public fetch. Nested symlinks are skipped. Invalid metadata produces warnings. Identical copies collapse; conflicting definitions stay inspectable. Public failures retain previous snapshots with warnings; removed local files disappear on refresh. HTTP clients cannot supply roots or URLs.

## Eligibility before scoring

1. Honor “no skills,” explicit skill exclusions, and simple negated clauses such as “not React.”
2. Require compatible framework, platform, service, or artifact. Browser React and React Native are distinct. SwiftUI implies Swift and Apple; it does not imply UIKit. Named services must match.
3. Require the relevant specialty. A framework mention cannot justify authentication, performance, or testing advice by itself. Broad skills are withheld on specialist tasks; artifact skills can still create/edit their own file type.
4. Check reviewed workflow prerequisites. Live Excel needs an open/active Excel workflow. Stripe Connect needs a marketplace, connected account, or payment-distribution context.
5. Require scope evidence. Unknown live names without recognizable scope are withheld. Reviewed general debugging/testing skills can cross platforms but need a technical task.

Explicit invocation (`$skill-name`, a distinctive `skill-name`, or “pdf skill”) takes priority and receives 100 for explicit request. Exclusion still wins. “PDF” alone is an artifact, not a skill invocation. Recommendation does not authorize a skill's commands.

## Fit score

| Criterion | Maximum | Rule |
| --- | ---: | --- |
| Task purpose | 30 | 30 for matching specialty; 20 for eligible general/artifact work |
| Platform or artifact | 25 | 25 specific match; 20 broader Swift/Apple/web/database scope; 15 eligible general-purpose skill |
| Description evidence | 25 | Five per distinct shared nontrivial term, capped at 25 |
| Specialist fit | 10 | 10 for one or two specialties; 5 for broader guidance |
| Available instructions | 10 | 10 installed; 7 imported public; 0 discovery metadata only |

Recommend eligible skills scoring **60/100 or above**, up to three. Explicit requests come first; other ties prefer closer scope, then stable ID order. Equivalent installed guidance has an availability advantage; stronger task evidence can still favor a public skill. Popularity does not influence `criteria-v2`.

Selection deduplicates names and includes additional skills only for a new purpose/platform combination. Three overlapping accessibility skills should not fill the list. A prompt addressing SwiftUI and React accessibility may receive one for each. A specialist addressing a bug also covers generic debugging. Explicit requests may select overlapping skills within the three-skill limit.

Expand **Why this skill** to see the total, threshold, and component scores. The response also explains the match and identifies the source. `confidence` is score/100 for compatibility, not a calibrated probability or security rating.

## Evaluation and limitations

`npm run eval` runs ten legacy public-search cases and twenty criteria cases covering concurrency, accessibility, native/browser React, persistence testing, release, artifacts, negation, invocation, abstention, and complementary skills. `npm test` also checks prerequisites, import validation, failures, and private instruction bodies. `npm run macos:test` verifies decoding and copy behavior. These are regression fixtures, not an accuracy benchmark.

Matching uses names, descriptions, a controlled vocabulary, and reviewed annotations. Full instruction bodies are stored for provenance, not used as executable policy or semantic matching evidence. Complex negation, unfamiliar technologies, other languages, and subtle context can still produce misses. Destination-app tool availability is unverified. Every skill remains `not-audited`; inspect the explanation and selection before copying.
