# Recommendation relevance

The default `criteria-v2` import-based matcher is documented in [Skill matching](SKILL_MATCHING.md). It adds twenty fixed cases and a five-part score, prerequisite gates, exclusions, and complementary selection. The historical results below describe the retained `heuristic-v1` public-search mode.

The first live demo recommended `clerk-nextjs-patterns` for a Next.js performance problem. The old ranker counted framework words without requiring evidence that an unknown skill addressed the actual task. It also treated browser React as interchangeable with React Native.

The updated ranker checks platform compatibility and task purpose separately. Unknown skills need a recognizable domain and, for a specialized task, a matching capability. Broad unknown names such as `vercel-optimize` are withheld because their platform scope is not established. Locally annotated general-purpose skills, such as systematic debugging, can work across platforms. Popularity never overrules relevance.

## Reproduce

```sh
npm test          # all backend tests, including the ten fixed relevance cases
npm run eval      # readable relevance report; no network or running server
npm run eval:live # three real public-search checks; no running server required
npm run smoke    # HTTP check against the running local server
```

The fixed evaluation uses a shared, deliberately noisy candidate pool. Some records came from the live public search; records under `evaluation/fixtures` are synthetic test cases, not installable packages. Each prompt defines required useful skills and an allowed set; missing or unrelated recommendations fail. Successful empty results are tested too. This is a regression suite, not an unbiased accuracy benchmark.

## Verified on September 30, 2026

The previous ranker passed 2/10 fixed cases; the updated ranker passed 10/10. All 25 backend tests passed, including request/response schema checks and HTTP validation.

| Fixed case | Useful result |
| --- | --- |
| Next.js performance | React best practices and Next.js performance |
| Next.js authentication | Clerk and authentication patterns |
| React tests | React Testing Library and general testing guidance |
| Python crash | Python debugging and systematic debugging |
| Postgres query performance | Postgres performance guidance |
| Landing-page design | Frontend design and web guidelines |
| React accessibility | React accessibility and web guidelines |
| SwiftUI accessibility | SwiftUI accessibility |
| React Native performance | Native performance and systematic debugging |
| Greeting | No skills |

The three live checks returned:

| Prompt | Recommendations | Analysis time |
| --- | --- | --- |
| Next.js performance | `vercel-react-best-practices`, `nextjs-performance` | 326 ms |
| Clerk authentication | `clerk-setup`, `clerk-custom-ui`, `clerk-backend-api` | 710 ms |
| React Native performance | `expo-react-native-performance` | 437 ms |

These are single-run observations, not latency guarantees. Public results can change. The native macOS app was also tested against the restarted backend with the original Next.js prompt: it displayed both performance skills, live-search provenance, and the new relevance explanations.

## Remaining limits

Names and curated tags are incomplete evidence. The ranker can miss useful skills with broad names or unrecognized technologies, cannot deeply understand negation or mixed tasks, and does not inspect `SKILL.md` content. The next increment should retrieve bounded public content and evaluate content-aware ranking against these same positive and negative cases. No skill is audited or automatically installed by this change.
