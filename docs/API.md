# API v1

Base URL: `http://127.0.0.1:8787`. `GET /health` returns `{"status":"ok","schemaVersion":"1.0"}`.

`POST /analyze` requires `Content-Type: application/json` and the [request schema](../contracts/analyze-request.schema.json). Unknown fields are rejected. `app` is context for future host-specific behavior; it does not affect ranking yet. `maxSkills` defaults to 3.

Successful responses follow the [response schema](../contracts/analyze-response.schema.json). `skills` may be empty. `confidence` is a heuristic relevance score, not a calibrated probability. `model.profile` is one of `fast`, `balanced`, `capable`; it is not a provider model ID. `effort.level` is `low`, `medium`, or `high`.

`meta.source` identifies `hybrid`, `installed`, `skills.sh`, `catalog`, or `none`. Default hybrid mode merges the imported library with live results; installed mode uses only installed imports. `meta.importedCount` optionally reports the library size. `skills[].provenance` additionally supports `installed` and `public-import`; installed skill URLs are local `file:` URLs. `skills[].evaluation` optionally contains `score`, `threshold`, and the five scored criteria. These v1 additions are optional to consumers.

In the legacy public-search modes, live search fans out over at most three controlled topic queries, with eight results per query and a timeout per request. Responses are deduplicated and ranked. Complete upstream failure uses the bundled catalog; partial failure returns available results with a warning. A successful empty search stays empty. No result is given a security-pass claim.

Legacy `heuristic-v1` ranking separates task purpose (such as performance, authentication, or testing) from platform. A specialized task requires a matching capability; platform-only matches are withheld. React Native does not imply browser React, and named services such as Clerk must be present in the task. Unknown skills need an identifiable domain; only annotated general-purpose catalog skills can omit it. Matching signals come from skill names and local catalog tags, not repository names. Popularity breaks equal-relevance ties. Returning fewer than `maxSkills` is intentional. `heuristic-v1` still identifies the same deterministic ranking family; the legacy response remains compatible.

Errors use `{"error":{"code":"INVALID_REQUEST","message":"…"}}`:

| HTTP | Meaning |
| --- | --- |
| 400 | Malformed JSON, empty/oversized prompt, unknown fields, invalid types |
| 403 | Browser Origin or non-local Host rejected |
| 404 | Unknown method/path |
| 413 | Body exceeds 64 KiB |
| 415 | Content type is not JSON |
| 500 | Unexpected internal failure |

The default `criteria-v2` ranker requires matching scope/purpose, checks prerequisites and exclusions, uses a 60/100 threshold, and avoids overlapping recommendations. See [the scoring rules](SKILL_MATCHING.md). No raw prompt or local instruction content leaves the API.

`GET /skills` returns counts, import warnings, scoring definitions, and skill metadata (no instruction bodies). `POST /skills/import` with an empty JSON object refreshes the locally configured roots and public sources. Its 1 KiB request limit rejects client-supplied paths/URLs. Both endpoints use the same local-host and origin protections. A failed public refresh retains the prior snapshot with a warning.

The backend reads `.env` from the repository root. Existing environment variables take precedence. `PORT` changes the API port; if changed, update `APIClient.endpoint` in the client as well. `SKILLS_TIMEOUT_MS` must be 100–10,000. `SKILLS_MODE` is `hybrid` (default), `installed`, `live`, or `offline`. Run `npm run skills:import` or use the app’s Skill library before analyzing imported skills.

No auth is implemented for this loopback-only scaffold. Requests and prompt text are not persisted. This API is for the native app and local CLI, not web pages.
