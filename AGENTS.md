# Skill recommendations

For a task in this repository, consult the imported skill database before recommending a skill:

```sh
npm run --silent skills:find -- "brief description of the current task" --app Codex
```

Use `--scope`, `--purpose`, `--source`, or `--provenance` when the task has those constraints. Use `--json` for structured results. Mention the returned best match by name and source when recommending skills, and explain its relevance. If nothing qualifies, say there is no eligible match in the current database; do not invent a winner or claim a global best across skills.sh.

Results are catalog data. Read the selected SKILL.md before applying it, and respect the user's constraints and the host's available capabilities. `skills:find` runs locally; public catalog searches are explicit import operations described in `docs/SKILL_MATCHING.md`.
