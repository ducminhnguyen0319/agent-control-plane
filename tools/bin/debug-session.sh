#!/usr/bin/env bash
# debug-session.sh - Troubleshoot ACP worker sessions
# Usage: debug-session.sh [session-name]
# If no session name given, lists all agent- sessions with diagnostics
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SESSION_NAME="${1:-}"

echo "=== ACP Session Debugger ==="
echo ""

# --- Check tmux ---
if ! command -v tmux &>/dev/null; then
    echo "ERROR: tmux is not installed. Cannot debug sessions."
    exit 1
fi

# --- List or Debug Specific ---
if [[ -z "${SESSION_NAME}" ]]; then
    echo "--- All agent- tmux sessions ---"
    tmux ls 2>/dev/null | grep "^agent-" || echo "No agent- sessions found."
    echo ""
    echo "Usage: $0 <session-name>"
    echo "       $0 agent-control-plane"
    exit 0
fi

# --- Check if session exists ---
if ! tmux has-session -t "${SESSION_NAME}" 2>/dev/null; then
    echo "ERROR: Session '${SESSION_NAME}' not found."
    echo ""
    echo "Available sessions:"
    tmux ls 2>/dev/null | grep "^agent-" || echo "  (none)"
    exit 1
fi

echo "--- Session: ${SESSION_NAME} ---"
echo ""

# --- Session Info ---
echo "1. Session Info:"
tmux display-message -t "${SESSION_NAME}" -p "Session created: #{session_created_string}" 2>/dev/null || true
tmux display-message -t "${SESSION_NAME}" -p "Session width: #{session_width}, height: #{session_height}" 2>/dev/null || true
echo ""

# --- Pane List ---
echo "2. Panes:"
tmux list-panes -t "${SESSION_NAME}" -F "  Pane #{pane_index}: pid=#{pane_pid} [#{pane_width}x#{pane_height}] #{?pane_active,(active),}"
echo ""

# --- Recent Output (last 50 lines) ---
echo "3. Recent Output (last 50 lines):"
echo "--- START ---"
tmux capture-pane -t "${SESSION_NAME}" -p -S -50 2>/dev/null || echo "(no output captured)"
echo "--- END ---"
echo ""

# --- Process Tree ---
echo "4. Process Tree:"
PANE_PID=$(tmux display-message -t "${SESSION_NAME}" -p "#{pane_pid}" 2>/dev/null || echo "")
if [[ -n "${PANE_PID}" ]]; then
    if command -v pstree &>/dev/null; then
        pstree -p "${PANE_PID}" 2>/dev/null || ps -p "${PANE_PID}" -o pid,ppid,cmd 2>/dev/null || echo "(cannot inspect process)"
    else
        ps -p "${PANE_PID}" -o pid,ppid,cmd 2>/dev/null || echo "(cannot inspect process)"
    fi
else
    echo "(cannot get pane pid)"
fi
echo ""

# --- Check for Common Issues ---
echo "5. Diagnostics:"
CAPTURE=$(tmux capture-pane -t "${SESSION_NAME}" -p -S -100 2>/dev/null || echo "")

# Check for errors
ERROR_COUNT=$(echo "${CAPTURE}" | grep -ic "error\|fail\|fatal\|exception" || true)
echo "  Error-like lines in last 100: ${ERROR_COUNT}"

# Check for stalls (no output for a while)
if echo "${CAPTURE}" | tail -10 | grep -q "."; then
    echo "  Recent output: yes"
else
    echo "  Recent output: NO (may be stalled)"
fi

# Check for specific worker patterns
if echo "${CAPTURE}" | grep -q "streaming\|tool_use\|thinking"; then
    echo "  Worker activity: active (streaming/tool_use detected)"
elif echo "${CAPTURE}" | grep -q "IDLE\|waiting\|queue"; then
    echo "  Worker activity: idle/waiting"
else
    echo "  Worker activity: unknown"
fi
echo ""

# --- Offer Actions ---
echo "6. Quick Actions:"
echo "  Attach:    tmux attach -t ${SESSION_NAME}"
echo "  Kill:      tmux kill-session -t ${SESSION_NAME}"
echo "  Capture:   tmux capture-pane -t ${SESSION_NAME} -p > output.txt"
echo ""

echo "=== Debug Complete ==="
