# API v1

Base URL: `http://127.0.0.1:8787`. `GET /health` returns `{"status":"ok","schemaVersion":"1.0"}`.

`POST /analyze` requires `Content-Type: application/json` and the [request schema](../contracts/analyze-request.schema.json). Unknown fields are rejected. `app` is context for future host-specific behavior; it does not affect ranking yet. `maxSkills` defaults to 3.

Successful responses follow the [response schema](../contracts/analyze-response.schema.json). `skills` may be empty. `confidence` is a heuristic relevance score, not a calibrated probability. `model.profile` is one of `fast`, `balanced`, `capable`; it is not a provider model ID. `effort.level` is `low`, `medium`, or `high`.

`meta.source` identifies `skills.sh`, `catalog`, or `none`. Live search fans out over at most three controlled topic queries, with eight results per query and a timeout per request. Responses are deduplicated and ranked. Complete upstream failure uses the bundled catalog; partial failure returns available results with a warning. A successful empty search stays empty. No result is given a security-pass claim.

Errors use `{"error":{"code":"INVALID_REQUEST","message":"…"}}`:

| HTTP | Meaning |
| --- | --- |
| 400 | Malformed JSON, empty/oversized prompt, unknown fields, invalid types |
| 403 | Browser Origin or non-local Host rejected |
| 404 | Unknown method/path |
| 413 | Body exceeds 64 KiB |
| 415 | Content type is not JSON |
| 500 | Unexpected internal failure |

The backend reads `.env` from the repository root. Existing environment variables take precedence. `PORT` changes the API port; if changed, update `APIClient.endpoint` in the client as well. `SKILLS_TIMEOUT_MS` must be 100–10,000. `SKILLS_MODE` is `live` or `offline`.

No auth is implemented for this loopback-only scaffold. Requests and prompt text are not persisted. This API is for the native app and local CLI, not web pages.
