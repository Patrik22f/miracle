# Claude Code integration

Preflight can recommend skills through Claude Code's documented `UserPromptSubmit` command hook. It runs when a prompt is submitted, before Claude processes it. It does not capture a partially typed terminal prompt. The native macOS panel still supports explicit capture/paste where Accessibility exposes the input.

1. Import the content. The default roots are `~/.codex/skills` and `~/.claude/skills`:

   ```sh
   npm run skills:import
   ```

   For project-local skills, explicitly include each desired root; repeated `--root` options replace the defaults:

   ```sh
   npm run skills:import -- --root "$HOME/.claude/skills" --root /absolute/project/.claude/skills
   ```

2. Generate the configuration fragment:

   ```sh
   npm run --silent claude:config
   ```

3. Merge the generated `hooks.UserPromptSubmit` entry into your project's `.claude/settings.local.json`. Preserve existing hooks, permissions and other settings. The generator only prints JSON and does not change your configuration. It quotes absolute Node/script paths, so the hook can run from a different working directory. Regenerate it after moving Preflight or changing Node installation paths.

The hook reads bounded context from the exact active-session transcript supplied by Claude and resolves short follow-ups against it. It filters session identity and branch ancestry, excludes tool/thinking content, and never scans other chats. Missing or unsupported transcripts fail open. See [context behavior and limits](CHAT_CONTEXT.md).

The hook reads Preflight's library directly; no local HTTP server or provider token is required. It sends names, source locations, fit scores and evidence line numbers as optional context. Public imports are explicitly marked as not installed. It does not paste the full skill, authorize tools, install packages, execute skill commands, or alter the prompt. Claude must read the exact source and respect its normal permission policy.

Malformed/oversized events, a missing or corrupt library, or an unrecognized task produce no output and exit successfully. The process has a 1.5-second deadline and the generated hook configuration has a two-second timeout. No prompts, session IDs or transcript paths are logged or persisted. Node's timer is cooperative during synchronous compilation; Claude's external timeout is the overall bound.

`/skill-name` supports explicit selection. `disable-model-invocation: true` requires that slash invocation; ordinary mentions or `$skill-name` cannot bypass it. `user-invocable: false` excludes direct slash invocation. Recognized Claude-only extensions are withheld from other hosts; known Codex-specific tool instructions are withheld from Claude. This is a conservative static check, not comprehensive runtime capability discovery. Imported Codex skills may be usable as readable instructions, but their presence does not register a Claude slash command. Configure project roots separately to avoid mixing project-specific skills from unrelated repositories.

Tests validate input/output protocol, manual invocation, compatibility, invalid inputs and safe failure. Live Claude Code acceptance and terminal live capture remain unverified.

References: [Claude skills](https://code.claude.com/docs/en/skills), [hooks](https://code.claude.com/docs/en/hooks#userpromptsubmit).
