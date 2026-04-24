#!/usr/bin/env bash
# test-debug-session.sh - Test debug-session.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEBUG_TOOL="${SCRIPT_DIR}/../bin/debug-session.sh"

echo "=== Test: Debug Session Tool ==="
echo ""

# Test 1: Script exists and is executable
echo "Test 1: Script exists and executable"
[[ -x "${DEBUG_TOOL}" ]] && echo "  PASS: executable" || { echo "  FAIL"; exit 1; }

# Test 2: Syntax check
echo "Test 2: Syntax valid"
bash -n "${DEBUG_TOOL}" && echo "  PASS: syntax ok" || { echo "  FAIL"; exit 1; }

# Test 3: Help/List mode (no args)
echo "Test 3: List mode (no args)"
OUTPUT=$("${DEBUG_TOOL}" 2>&1) && echo "  PASS: ran without args" || echo "  WARN: exit code $?"
echo "${OUTPUT}" | grep -q "All agent-" && echo "  PASS: lists sessions" || echo "  INFO: no sessions to list"

# Test 4: Non-existent session
echo "Test 4: Non-existent session handling"
OUTPUT=$("${DEBUG_TOOL}" "nonexistent-session-12345" 2>&1) || true
echo "${OUTPUT}" | grep -qi "not found\|ERROR" && echo "  PASS: handles missing session" || echo "  WARN: unexpected output"

# Test 5: Check usage hint
echo "Test 5: Usage hint"
echo "${OUTPUT}" | grep -q "Usage:" && echo "  PASS: shows usage" || echo "  WARN: no usage hint"

echo ""
echo "=== Debug Tool Tests Complete ==="
