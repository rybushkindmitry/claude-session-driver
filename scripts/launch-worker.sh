#!/bin/bash
set -euo pipefail

# Launches a Claude Code worker session in a detached tmux session with the
# session-driver plugin loaded for lifecycle event emission.
#
# Usage: launch-worker.sh <tmux-name> <working-dir> [extra claude args...]

TMUX_NAME="${1:?Usage: launch-worker.sh <tmux-name> <working-dir> [extra claude args...]}"
WORKING_DIR="${2:?Usage: launch-worker.sh <tmux-name> <working-dir> [extra claude args...]}"
shift 2
EXTRA_ARGS=("$@")

# Resolve plugin directory (parent of scripts/)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Resolve working directory to absolute physical path (resolves symlinks)
WORKING_DIR="$(cd "$WORKING_DIR" && pwd -P)"

# Generate session ID
SESSION_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')

# Ensure output directory exists
mkdir -p /tmp/claude-workers

# Write metadata
jq -n \
  --arg tmux_name "$TMUX_NAME" \
  --arg session_id "$SESSION_ID" \
  --arg cwd "$WORKING_DIR" \
  --arg started_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  '{tmux_name: $tmux_name, session_id: $session_id, cwd: $cwd, started_at: $started_at}' \
  > "/tmp/claude-workers/${SESSION_ID}.meta"

# Check for existing tmux session with this name
if tmux has-session -t "$TMUX_NAME" 2>/dev/null; then
  echo "Error: tmux session '$TMUX_NAME' already exists" >&2
  rm -f "/tmp/claude-workers/${SESSION_ID}.meta"
  exit 1
fi

# Propagate approval timeout through tmux to the hook environment
APPROVAL_TIMEOUT="${CLAUDE_SESSION_DRIVER_APPROVAL_TIMEOUT:-30}"

# Launch claude in detached tmux session with permission bypass.
# The PreToolUse hook provides controller-based gating, so the built-in
# interactive permission dialog is redundant and would block the worker.
tmux new-session -d -s "$TMUX_NAME" -c "$WORKING_DIR" \
  -e "CLAUDE_SESSION_DRIVER_APPROVAL_TIMEOUT=$APPROVAL_TIMEOUT" \
  claude --session-id "$SESSION_ID" --plugin-dir "$PLUGIN_DIR" --dangerously-skip-permissions "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}"

# Accept the workspace trust dialog (default selection is "Yes, I trust this folder")
sleep 3
tmux send-keys -t "$TMUX_NAME" Enter

# Wait for session to start
WAIT_SCRIPT="$SCRIPT_DIR/wait-for-event.sh"
if ! bash "$WAIT_SCRIPT" "$SESSION_ID" session_start 30 > /dev/null; then
  echo "Error: Worker session failed to start within 30 seconds" >&2
  tmux kill-session -t "$TMUX_NAME" 2>/dev/null || true
  rm -f "/tmp/claude-workers/${SESSION_ID}.meta" "/tmp/claude-workers/${SESSION_ID}.events.jsonl"
  exit 1
fi

# Output session info
jq -n \
  --arg session_id "$SESSION_ID" \
  --arg tmux_name "$TMUX_NAME" \
  --arg events_file "/tmp/claude-workers/${SESSION_ID}.events.jsonl" \
  '{session_id: $session_id, tmux_name: $tmux_name, events_file: $events_file}'
