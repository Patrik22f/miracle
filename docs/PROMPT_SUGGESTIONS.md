# Zázrak prompt suggestions

Zázrak suggests three concrete next tasks using the current project code, unsent prompt, and available chat context. **Use draft** puts a suggestion into Zázrak's editable prompt and starts existing skill/model advice. **Copy prompt** copies it for review in the host app. Neither action sends a message or changes project files.

## Setup

1. Add `GROQ_API_KEY` to the ignored local `.env`. `GROQ_MODEL` defaults to `openai/gpt-oss-120b`, following the Notamhelp client. Restart `npm start` after changing it.
2. Open **Your next task → Choose a project**, or **Settings → Prompts**. Choose the code folder once; the selection is remembered independently of skill installation.
3. Leave **Suggest prompts automatically** enabled. The existing global automatic-recommendations switch pauses both features. Demo mode and setup/settings suspend background suggestions.

When Cursor or Codex exposes a local file URL as its focused window's Accessibility document, Zázrak can resolve its enclosing Git repository or package automatically. **Follow the active project's document** removes the manual folder override. Not every host exposes this information; Zázrak asks for a folder rather than guessing from recent projects or other chats. A manually selected folder remains selected when switching apps; the UI labels it **Selected project**. Unsaved editor buffers are not indexed; save files for the next scan.

## Context and latency

- Waits for a 1.2-second prompt pause, then checks the selected folder every 15 seconds while active. Changes to prompt, chat, project, preferences or suspension cancel the client task and reject late responses.
- Git projects use `git ls-files` with standard ignore rules for untracked files. Tracked source remains eligible unless excluded below. Folder projects use a bounded directory walk. Git failures fail closed rather than bypassing ignores.
- Indexes up to 3,000 eligible file metadata records, includes up to 1,000 relative paths and 80 changed paths, and reads up to 18 excerpts within a 48,000-byte budget (3,600 bytes per file). README/manifests, modified files, and paths related to the prompt receive priority. Oversized files, binary data, dot directories/files, common secret filenames, symlinks, dependencies and generated folders are excluded.
- File metadata, sampled content and Git HEAD form a revision. Suggestions are cached in memory by revision, prompt, chat and model; unchanged polling does not call Groq. Concurrent identical requests share work. Remote requests are at least 15 seconds apart; HTTP 429 respects a bounded cooldown.
- Groq uses low reasoning effort for GPT-OSS, strict JSON schema for GPT-OSS (JSON mode for other models), a 2,200-token completion budget and a 10-second deadline. Results must contain exactly three distinct suggestions, each referencing an actually sampled file. Proposed new filenames are removed from the evidence list; suggestions with no remaining sampled evidence are rejected. Invalid output is rejected and retried on a later poll.

The UI shows sampled/indexed counts. This is a periodically refreshed, bounded view of the code, not complete knowledge of every file. Suggestions are proposals, not verified findings. They do not run builds or tests.

## Data flow

This optional feature changes the previous local-only data flow: selected source excerpts, relative filenames, project folder name, current prompt and supplied chat context go to **Groq** over HTTPS. Common credential strings are redacted, but redaction cannot guarantee removal of every sensitive value. Choose an appropriate project. The absolute root stays between the native app and loopback backend. Groq credentials stay in the backend environment; no keys are embedded in the app, returned through the API, or logged. Prompts, code and suggestions are not persisted by Zázrak. Only the folder and preference persist. The service keeps at most 12 successful results in memory, cleared on restart.

Skill matching remains independent and local in knowledge mode. A missing key, inaccessible folder, timeout, unavailable model or malformed provider output produces a visible status without interrupting skill recommendations. The API continues to reject browser origins and non-loopback hosts.

## API and checks

The [request schema](../contracts/suggestions-request.schema.json) and [response schema](../contracts/suggestions-response.schema.json) define the wire contract.

`POST /suggestions` accepts `{ "projectPath": "/absolute/project", "prompt": "optional draft", "context": { ... } }`. The context format is the same as `/analyze`; an empty prompt is valid. The response has `schemaVersion`, `status`, `provider`, `model`, `suggestions`, `retryAfterMs`, and optional `project`, `summary`, `cached`, `generatedAt`, `message` fields. Status is `ready`, `setup`, `empty`, `waiting` or `error`. Invalid requests return 400; unreadable projects return 422. Existing `/analyze` clients remain compatible.

```sh
npm test
npm run macos:test
npm run smoke:suggestions -- /absolute/project # live Groq call; sends selected context
```

The live smoke test reports duration, titles and cache behavior without printing credentials or source. Provider docs: [chat completions](https://console.groq.com/docs/api-reference), [structured output](https://console.groq.com/docs/structured-outputs).
