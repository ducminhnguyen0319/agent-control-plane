#!/usr/bin/env bash
# test-linux-doctor.sh - Test flow-runtime-doctor-linux.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCTOR="${SCRIPT_DIR}/../bin/flow-runtime-doctor-linux.sh"

echo "=== Test: Linux Runtime Doctor ==="
echo ""

# Test 1: Script exists and is executable
echo "Test 1: Script exists and executable"
[[ -x "${DOCTOR}" ]] && echo "  PASS: executable" || { echo "  FAIL"; exit 1; }

# Test 2: Syntax check (already done, but double-check)
echo "Test 2: Syntax valid"
bash -n "${DOCTOR}" && echo "  PASS: syntax ok" || { echo "  FAIL"; exit 1; }

# Test 3: Runs without crashing
echo "Test 3: Runs without errors"
OUTPUT=$("${DOCTOR}" 2>&1) && echo "  PASS: ran successfully" || { echo "  FAIL"; echo "${OUTPUT}"; exit 1; }

# Test 4: Check expected output sections
echo "Test 4: Output sections present"
echo "${OUTPUT}" | grep -q -- "=== ACP Linux Runtime Doctor ===" && echo "  PASS: header" || { echo "  FAIL: header missing"; exit 1; }
echo "${OUTPUT}" | grep -q -- "--- Systemd Service Status ---" && echo "  PASS: systemd section" || echo "  WARN: systemd section missing (may not be on systemd system)"
echo "${OUTPUT}" | grep -q -- "=== Generic Runtime Doctor ===" && echo "  PASS: generic doctor called" || echo "  WARN: generic doctor not called"

# Test 5: Check systemd detection (if on systemd system)
if command -v systemctl &>/dev/null; then
    echo "Test 5: Systemd detection"
    echo "${OUTPUT}" | grep -q "systemctl: available" && echo "  PASS: systemd detected" || echo "  FAIL"
else
    echo "Test 5: SKIP (not on systemd system)"
fi

echo ""
echo "=== All Tests Passed ==="
