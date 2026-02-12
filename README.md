# claude-session-driver

A Claude Code plugin that gives Claude the ability to spawn, orchestrate, and supervise other Claude Code sessions.

## Why

A single Claude session can only do one thing at a time. This plugin lets a "controller" Claude launch "worker" Claude sessions in tmux, send them tasks, monitor their progress, review and approve their tool calls, and read their results. The controller can delegate work, fan out across parallel workers, chain workers in pipelines, or hand a running session off to a human.

## How It Works

The plugin installs hooks into each worker session that emit lifecycle events (session start, prompt submitted, tool use, stop, session end) to a JSONL file. A PreToolUse hook gives the controller a window to inspect and approve or deny every tool call before it executes — auto-approving after a configurable timeout so workers never hang.

The controller drives workers through shell scripts that handle tmux management, event polling, session logs, and cleanup.

## Installation

```bash
claude /install claude-session-driver@superpowers-marketplace
```

Requires **tmux**, **jq**, and the **claude** CLI.

## Usage

Once installed, the `driving-claude-code-sessions` skill teaches Claude how to use the plugin. The skill covers:

- Launching and stopping workers
- Single-turn and multi-turn conversations
- Fan-out parallelism (multiple workers on independent tasks)
- Pipelines (chaining workers where one's output feeds the next)
- Tool call approval and denial
- Reading worker event streams and conversation logs
- Handing off a live session to a human operator

## Scripts

All orchestration happens through these scripts in the `scripts/` directory:

| Script | Description |
|--------|-------------|
| `launch-worker.sh` | Start a worker session in tmux |
| `converse.sh` | Send a prompt, wait for completion, return the response |
| `send-prompt.sh` | Send a prompt without waiting |
| `wait-for-event.sh` | Block until a specific lifecycle event appears |
| `read-events.sh` | Read and filter the event stream |
| `read-turn.sh` | Format the last conversation turn as markdown |
| `stop-worker.sh` | Gracefully stop a worker and clean up |
| `approve-tool.sh` | Approve or deny a pending tool call |

## License

MIT
