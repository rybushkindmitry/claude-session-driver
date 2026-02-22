#!/bin/bash
set -euo pipefail

SESSION_ID="${1:?Usage: wait-for-event.sh <session-id> <event-type> [timeout] [--after-line N]}"
EVENT_TYPE="${2:?Usage: wait-for-event.sh <session-id> <event-type> [timeout] [--after-line N]}"
TIMEOUT="${3:-60}"

AFTER_LINE=0
shift 3 2>/dev/null || shift $#
while [ $# -gt 0 ]; do
  case "$1" in
    --after-line) AFTER_LINE="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/lib"
# shellcheck source=lib/transport.sh
source "$LIB_DIR/transport.sh"
csd_load_target "$SESSION_ID"

EVENT_FILE="/tmp/claude-workers/${SESSION_ID}.events.jsonl"
DEADLINE=$((SECONDS + TIMEOUT))

if [ "${WORKER_TARGET:-local}" = "local" ] || [ -z "${WORKER_TARGET:-}" ]; then
  # Local: existing line-counting approach
  while [ ! -f "$EVENT_FILE" ]; do
    [ "$SECONDS" -ge "$DEADLINE" ] && { echo "Timeout waiting for event file" >&2; exit 1; }
    sleep 0.5
  done

  LINES_CHECKED=$AFTER_LINE
  while [ "$SECONDS" -lt "$DEADLINE" ]; do
    CURRENT_LINES=$(wc -l < "$EVENT_FILE" | tr -d ' ')
    if [ "$CURRENT_LINES" -gt "$LINES_CHECKED" ]; then
      MATCH=$(tail -n +"$((LINES_CHECKED + 1))" "$EVENT_FILE" \
        | jq -c "select(.event == \"$EVENT_TYPE\")" 2>/dev/null \
        | head -1)
      [ -n "$MATCH" ] && { echo "$MATCH"; exit 0; }
      LINES_CHECKED=$CURRENT_LINES
    fi
    sleep 0.5
  done
else
  # Remote: stream via transport_tail, filter locally
  MATCH_FILE=$(mktemp)
  transport_tail "$EVENT_FILE" | while IFS= read -r line; do
    [ "$SECONDS" -ge "$DEADLINE" ] && exit 1
    EVENT=$(echo "$line" | jq -r '.event // empty' 2>/dev/null) || continue
    if [ "$EVENT" = "$EVENT_TYPE" ]; then
      echo "$line" > "$MATCH_FILE"
      exit 0
    fi
  done || true
  if [ -s "$MATCH_FILE" ]; then
    cat "$MATCH_FILE"
    rm -f "$MATCH_FILE"
    exit 0
  fi
  rm -f "$MATCH_FILE"
fi

echo "Timeout waiting for event '$EVENT_TYPE' (${TIMEOUT}s)" >&2
exit 1
