# claude-session-driver

A Claude Code plugin for launching, controlling, and monitoring other Claude Code sessions as workers via tmux.

## What It Does

Spawn worker Claude Code sessions in tmux, send them prompts, monitor their lifecycle through events, read their output, approve or deny tool calls, and hand off to human operators.

Workers are full Claude Code sessions with a plugin that emits lifecycle events (session start, prompt submitted, tool use, stop, session end) to a JSONL file. A PreToolUse hook gives the controller a window to inspect and approve/deny every tool call.

## Prerequisites

- **tmux** - for running worker sessions
- **jq** - for JSON parsing
- **claude** CLI - Claude Code

## Installation

```bash
claude /install claude-session-driver@superpowers-marketplace
```

## Quick Start

```bash
SCRIPTS="/path/to/claude-session-driver/scripts"

# Launch a worker
RESULT=$("$SCRIPTS/launch-worker.sh" my-worker ~/project)
SESSION_ID=$(echo "$RESULT" | jq -r '.session_id')

# Send a prompt and get the response
RESPONSE=$("$SCRIPTS/converse.sh" my-worker "$SESSION_ID" "Run the tests" 300)
echo "$RESPONSE"

# Stop the worker
"$SCRIPTS/stop-worker.sh" my-worker "$SESSION_ID"
```

## Scripts

| Script | Usage | Description |
|--------|-------|-------------|
| `converse.sh` | `<tmux-name> <session-id> <prompt> [timeout=120]` | Send prompt, wait, return response |
| `launch-worker.sh` | `<tmux-name> <working-dir> [claude-args...]` | Start a worker session |
| `send-prompt.sh` | `<tmux-name> <prompt-text>` | Send a prompt to a worker |
| `wait-for-event.sh` | `<session-id> <event-type> [timeout=60] [--after-line N]` | Block until event or timeout |
| `read-events.sh` | `<session-id> [--last N] [--type T] [--follow]` | Read event stream |
| `read-turn.sh` | `<session-id> [--full]` | Format last turn as markdown |
| `stop-worker.sh` | `<tmux-name> <session-id>` | Gracefully stop and clean up |
| `approve-tool.sh` | `<session-id> <allow\|deny>` | Respond to a pending tool approval |

## Skill

Install the plugin and the `driving-claude-code-sessions` skill becomes available. It provides full documentation for orchestrating worker sessions, including patterns for fan-out parallelism, pipelines, supervised multi-turn conversations, and human handoff.

## License

MIT
