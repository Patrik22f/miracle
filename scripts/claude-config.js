#!/usr/bin/env node
import { fileURLToPath } from 'node:url';
// Generate a reviewable fragment. Never replace the user's existing hooks,
// permissions, environment or managed policy settings.
const quote = value => "'" + value.replaceAll("'", "'\\''") + "'";
const command = `${quote(process.execPath)} ${quote(fileURLToPath(new URL('./claude-hook.js', import.meta.url)))}`;
console.log(JSON.stringify({ hooks: { UserPromptSubmit: [{ hooks: [{ type: 'command', command, timeout: 2 }] }] } }, null, 2));
