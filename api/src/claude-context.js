import { open, realpath } from 'node:fs/promises';
import { constants } from 'node:fs';
import { extname, isAbsolute } from 'node:path';
import { contextLimits } from './task-context.js';

// Read only the exact session transcript supplied by Claude's hook. Never scan
// other chats, tool output, project directories, or credential stores.
export async function readClaudeContext(event) {
  if (event?.hook_event_name !== 'UserPromptSubmit' || typeof event.session_id !== 'string'
    || !/^[a-zA-Z0-9-]{1,128}$/.test(event.session_id) || typeof event.transcript_path !== 'string'
    || !isAbsolute(event.transcript_path) || extname(event.transcript_path) !== '.jsonl') return undefined;
  let file;
  try {
    if (await realpath(event.transcript_path) !== event.transcript_path) return undefined;
    file = await open(event.transcript_path, constants.O_RDONLY | constants.O_NOFOLLOW);
    const info = await file.stat();
    if (!info.isFile()) return undefined;
    const size = Math.min(info.size, 256 * 1024), start = info.size - size;
    const buffer = Buffer.alloc(size);
    const { bytesRead } = await file.read(buffer, 0, size, start);
    let lines = buffer.subarray(0, bytesRead).toString('utf8').split('\n');
    if (start > 0) lines.shift(); // A partial first record cannot supply context.
    const records = [];
    for (const line of lines) {
      let record; try { record = JSON.parse(line); } catch { continue; }
      if (record.sessionId !== event.session_id || record.isSidechain || !['user', 'assistant'].includes(record.type)
        || typeof record.uuid !== 'string' || !record.message) continue;
      const content = typeof record.message.content === 'string' ? record.message.content
        : Array.isArray(record.message.content) ? record.message.content.filter(block => block.type === 'text' && typeof block.text === 'string').map(block => block.text).join('\n') : '';
      // Keep tool-only nodes for ancestry, but never include their contents.
      records.push({ uuid: record.uuid, parentUuid: record.parentUuid, role: record.type, content });
    }
    if (!records.length) return undefined;
    const byID = new Map(records.map(record => [record.uuid, record]));
    const branch = [], seen = new Set();
    let current = records.at(-1);
    while (current && !seen.has(current.uuid)) {
      seen.add(current.uuid); branch.unshift(current); current = byID.get(current.parentUuid);
    }
    // Claude may have appended the currently submitted prompt already.
    if (branch.at(-1)?.role === 'user' && branch.at(-1).content === event.prompt) branch.pop();
    const textBranch = branch.filter(row => row.content.trim());
    const messages = []; let remaining = contextLimits.characters;
    for (const record of textBranch.slice(-contextLimits.turns).reverse()) {
      if (!remaining) break;
      const content = record.content.slice(-Math.min(contextLimits.messageCharacters, remaining));
      remaining -= content.length; messages.unshift({ role: record.role, content });
    }
    if (!messages.length) return undefined;
    return { conversationId: event.session_id, source: 'claude-transcript', messages,
      truncated: start > 0 || Boolean(branch[0]?.parentUuid) || textBranch.length > messages.length || textBranch.some(row => row.content.length > contextLimits.messageCharacters) };
  } catch { return undefined; }
  finally { await file?.close(); }
}
