Please read my global conversation history and present it in an easy-to-scan format.

Locate the history file by checking, in order:
1. `$CLAUDE_CONFIG_DIR/history.jsonl` if `CLAUDE_CONFIG_DIR` is set
2. `~/.claude/history.jsonl`
3. `~/.claude-personal/history.jsonl`
4. `~/.claude-work/history.jsonl`

Use the first one that exists. If none are found, say so and stop.

For each conversation, show:
- Entry number
- Date/time (human readable format: "Nov 10, 2025 15:48")
- Project name (just the folder name, not full path)
- First 60-80 characters of the conversation topic
- Session ID (if available)

**Group entries by `sessionId` and pick the FIRST non-meta prompt per session** as the topic.
A prompt is "meta" if its `display` (trimmed) starts with `/` or `!`, or equals (case-insensitive) one of: `quit`, `exit`, `yes`, `no`, `y`, `n`, or is empty.
If a session has only meta prompts, fall back to the most recent prompt for that session.
Without this filter, most sessions show `/quit` or `/exit` because those tend to be the last entry per session.

Sort sessions by the timestamp of the selected prompt, most recent first.

IMPORTANT: Format as a plain text table with properly padded columns (NOT markdown tables).

Focus on the most recent 10 conversations in the first table. If there are more, show another 5-7 in an "Additional Recent Conversations" table.

At the end, include:
---
Tip: Resume any conversation by running:
- claude --resume <session-id>
- claude --resume (to see an interactive list of recent sessions)
