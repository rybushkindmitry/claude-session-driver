#!/bin/bash
set -euo pipefail

# Sends a prompt to a Claude Code worker session running in tmux.
# Uses literal mode (-l) to prevent tmux from interpreting prompt content as key names.
#
# Usage: send-prompt.sh <tmux-name> <prompt-text>

TMUX_NAME="${1:?Usage: send-prompt.sh <tmux-name> <prompt-text>}"
PROMPT_TEXT="${2:?Usage: send-prompt.sh <tmux-name> <prompt-text>}"

# Verify tmux session exists
if ! tmux has-session -t "$TMUX_NAME" 2>/dev/null; then
  echo "Error: tmux session '$TMUX_NAME' does not exist" >&2
  exit 1
fi

# Send prompt text literally (no tmux key interpretation)
tmux send-keys -t "$TMUX_NAME" -l "$PROMPT_TEXT"

# Send Enter separately
tmux send-keys -t "$TMUX_NAME" Enter
