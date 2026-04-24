#!/usr/bin/env bash
# flow-runtime-doctor-linux.sh - Linux-specific runtime validation for ACP
# Checks systemd services, Linux paths, and runtime health
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-config-lib.sh"

FLOW_SKILL_DIR="$(resolve_flow_skill_dir "${BASH_SOURCE[0]}")"
CONTROL_PLANE_NAME="$(flow_canonical_skill_name)"
RUNTIME_HOME="$(resolve_runtime_home)"

echo "=== ACP Linux Runtime Doctor ==="
echo ""

# --- Systemd Checks ---
echo "--- Systemd Service Status ---"
if command -v systemctl &>/dev/null; then
    echo "systemctl: available"
    
    # Check user services (systemd --user)
    if systemctl --user is-active --quiet "${CONTROL_PLANE_NAME}.service" 2>/dev/null; then
        echo "service ${CONTROL_PLANE_NAME}: active (user)"
    elif systemctl --user is-enabled --quiet "${CONTROL_PLANE_NAME}.service" 2>/dev/null; then
        echo "service ${CONTROL_PLANE_NAME}: installed but not running (user)"
    else
        echo "service ${CONTROL_PLANE_NAME}: not installed (user)"
    fi
    
    # Check system services (if installed system-wide)
    if systemctl is-active --quiet "${CONTROL_PLANE_NAME}.service" 2>/dev/null; then
        echo "service ${CONTROL_PLANE_NAME}: active (system)"
    fi
else
    echo "systemctl: NOT available (not a systemd-based system?)"
fi
echo ""

# --- Linux Path Checks ---
echo "--- Linux Path Validation ---"
echo "RUNTIME_HOME=${RUNTIME_HOME}"
echo "FLOW_SKILL_DIR=${FLOW_SKILL_DIR}"

# Check XDG paths (Linux standard)
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

echo "XDG_CONFIG_HOME=${XDG_CONFIG_HOME}"
echo "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR}"

if [[ -d "${XDG_RUNTIME_DIR}" ]]; then
    echo "XDG_RUNTIME_DIR: exists"
else
    echo "XDG_RUNTIME_DIR: NOT FOUND (may cause issues with user services)"
fi
echo ""

# --- Process Checks ---
echo "--- Process Checks ---"
if command -v pgrep &>/dev/null; then
    AGENT_PIDS=$(pgrep -f "agent-control-plane" 2>/dev/null || true)
    if [[ -n "${AGENT_PIDS}" ]]; then
        echo "agent-control-plane processes running: yes (PIDs: ${AGENT_PIDS})"
        ps -p "${AGENT_PIDS}" -o pid,ppid,cmd 2>/dev/null || true
    else
        echo "agent-control-plane processes running: no"
    fi
else
    echo "pgrep: NOT available"
fi
echo ""

# --- tmux Checks ---
echo "--- tmux Session Checks ---"
if command -v tmux &>/dev/null; then
    echo "tmux: available ($(tmux -V))"
    TMUX_SESSIONS=$(tmux ls 2>/dev/null | grep -c "agent-" || true)
    echo "agent- tmux sessions: ${TMUX_SESSIONS}"
    if [[ ${TMUX_SESSIONS} -gt 0 ]]; then
        tmux ls 2>/dev/null | grep "agent-" || true
    fi
else
    echo "tmux: NOT installed (required for ACP worker sessions)"
fi
echo ""

# --- Socket/Port Checks ---
echo "--- Socket/Port Checks ---"
if command -v ss &>/dev/null; then
    echo "Checking for dashboard port (3180)..."
    ss -tlnp 2>/dev/null | grep ":3180 " || echo "Port 3180: not in use"
elif command -v netstat &>/dev/null; then
    netstat -tlnp 2>/dev/null | grep ":3180 " || echo "Port 3180: not in use"
else
    echo "ss/netstat: NOT available, skipping port check"
fi
echo ""

# --- Log File Checks ---
echo "--- Log File Checks ---"
LOG_DIR="${RUNTIME_HOME}/logs"
if [[ -d "${LOG_DIR}" ]]; then
    echo "LOG_DIR=${LOG_DIR}: exists"
    LOG_COUNT=$(find "${LOG_DIR}" -name "*.log" 2>/dev/null | wc -l)
    echo "Log files: ${LOG_COUNT}"
else
    echo "LOG_DIR=${LOG_DIR}: NOT FOUND"
fi
echo ""

# --- Run Generic Doctor ---
echo "=== Generic Runtime Doctor ==="
if [[ -f "${SCRIPT_DIR}/flow-runtime-doctor.sh" ]]; then
    bash "${SCRIPT_DIR}/flow-runtime-doctor.sh"
else
    echo "flow-runtime-doctor.sh: NOT FOUND"
fi

echo ""
echo "=== Linux Doctor Complete ==="
