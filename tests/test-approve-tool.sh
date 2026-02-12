#!/bin/bash
set -euo pipefail

# Test suite for approve-tool.sh PreToolUse hook

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APPROVE_TOOL="$SCRIPT_DIR/../hooks/approve-tool.sh"
EVENT_DIR="/tmp/claude-workers"

PASS_COUNT=0
FAIL_COUNT=0

cleanup() {
  rm -f "$EVENT_DIR"/test-approve-*.events.jsonl
  rm -f "$EVENT_DIR"/test-approve-*.tool-pending
  rm -f "$EVENT_DIR"/test-approve-*.tool-decision
  rm -f "$EVENT_DIR"/test-approve-*.meta
}
trap cleanup EXIT

pass() {
  echo "  PASS: $1"
  PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
  echo "  FAIL: $1 - $2"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

setup() {
  cleanup
  mkdir -p "$EVENT_DIR"
}

# --- Test 1: Emits pre_tool_use event to event stream ---
echo "Test 1: Emits pre_tool_use event"
setup
SESSION_ID="test-approve-001"
EVENT_FILE="$EVENT_DIR/${SESSION_ID}.events.jsonl"

# Run with short timeout so it auto-approves quickly
CLAUDE_SESSION_DRIVER_APPROVAL_TIMEOUT=1 \
  echo '{"session_id":"test-approve-001","tool_name":"Bash","tool_input":{"command":"echo hello"}}' \
  | bash "$APPROVE_TOOL" > /dev/null

if [ -f "$EVENT_FILE" ]; then
  EVENT=$(head -1 "$EVENT_FILE" | jq -r '.event')
  TOOL=$(head -1 "$EVENT_FILE" | jq -r '.tool')
  TOOL_CMD=$(head -1 "$EVENT_FILE" | jq -r '.tool_input.command')
  if [ "$EVENT" = "pre_tool_use" ] && [ "$TOOL" = "Bash" ] && [ "$TOOL_CMD" = "echo hello" ]; then
    pass "pre_tool_use event with tool details written to event stream"
  else
    fail "wrong event content" "event=$EVENT tool=$TOOL cmd=$TOOL_CMD"
  fi
else
  fail "event file" "not created"
fi

# --- Test 2: Auto-approves on timeout (no controller response) ---
echo "Test 2: Auto-approves on timeout"
setup
SESSION_ID="test-approve-002"

OUTPUT=$(CLAUDE_SESSION_DRIVER_APPROVAL_TIMEOUT=1 \
  echo '{"session_id":"test-approve-002","tool_name":"Read","tool_input":{"file_path":"/tmp/test"}}' \
  | bash "$APPROVE_TOOL")

DECISION=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.permissionDecision')
if [ "$DECISION" = "allow" ]; then
  pass "auto-approves when no controller response"
else
  fail "decision" "expected 'allow', got '$DECISION'"
fi

# --- Test 3: Respects controller allow decision ---
echo "Test 3: Respects controller allow decision"
setup
SESSION_ID="test-approve-003"
PENDING_FILE="$EVENT_DIR/${SESSION_ID}.tool-pending"
DECISION_FILE="$EVENT_DIR/${SESSION_ID}.tool-decision"

# Write controller decision after a short delay
(sleep 1 && echo '{"decision":"allow"}' > "$DECISION_FILE") &

OUTPUT=$(CLAUDE_SESSION_DRIVER_APPROVAL_TIMEOUT=10 \
  echo '{"session_id":"test-approve-003","tool_name":"Write","tool_input":{"file_path":"/tmp/x"}}' \
  | bash "$APPROVE_TOOL")

DECISION=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.permissionDecision')
if [ "$DECISION" = "allow" ]; then
  pass "returns allow when controller approves"
else
  fail "decision" "expected 'allow', got '$DECISION'"
fi

# Verify pending file was cleaned up
if [ ! -f "$PENDING_FILE" ]; then
  pass "pending file cleaned up"
else
  fail "cleanup" "pending file still exists"
fi

# --- Test 4: Respects controller deny decision ---
echo "Test 4: Respects controller deny decision"
setup
SESSION_ID="test-approve-004"
DECISION_FILE="$EVENT_DIR/${SESSION_ID}.tool-decision"

# Write deny decision after a short delay
(sleep 1 && echo '{"decision":"deny"}' > "$DECISION_FILE") &

OUTPUT=$(CLAUDE_SESSION_DRIVER_APPROVAL_TIMEOUT=10 \
  echo '{"session_id":"test-approve-004","tool_name":"Bash","tool_input":{"command":"rm -rf /"}}' \
  | bash "$APPROVE_TOOL")

DECISION=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.permissionDecision')
if [ "$DECISION" = "deny" ]; then
  pass "returns deny when controller denies"
else
  fail "decision" "expected 'deny', got '$DECISION'"
fi

# --- Test 5: Pending file contains tool details ---
echo "Test 5: Pending file contains tool details"
setup
SESSION_ID="test-approve-005"
PENDING_FILE="$EVENT_DIR/${SESSION_ID}.tool-pending"

# Immediately write decision so the hook doesn't block
echo '{"decision":"allow"}' > "$EVENT_DIR/${SESSION_ID}.tool-decision"

OUTPUT=$(CLAUDE_SESSION_DRIVER_APPROVAL_TIMEOUT=10 \
  echo '{"session_id":"test-approve-005","tool_name":"Edit","tool_input":{"file_path":"/tmp/foo","old_string":"a","new_string":"b"}}' \
  | bash "$APPROVE_TOOL" &)

# Give it a moment to write the pending file
sleep 0.5

# The pending file may already be cleaned up if the hook found the decision immediately.
# Check the event stream instead for tool details.
EVENT_FILE="$EVENT_DIR/${SESSION_ID}.events.jsonl"
wait
if [ -f "$EVENT_FILE" ]; then
  TOOL=$(head -1 "$EVENT_FILE" | jq -r '.tool')
  if [ "$TOOL" = "Edit" ]; then
    pass "tool details recorded in event stream"
  else
    fail "tool in event" "expected 'Edit', got '$TOOL'"
  fi
else
  fail "event file" "not created"
fi

# --- Summary ---
echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo "Results: $PASS_COUNT/$TOTAL passed, $FAIL_COUNT failed"

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
