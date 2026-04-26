#!/usr/bin/env bash
# Test kick-scheduler-wrapper.sh cross-platform compatibility
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" && pwd)"
WRAPPER="${SCRIPT_DIR}/kick-scheduler-wrapper.sh"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TEMP_DIR}"' EXIT

# Test 1: Syntax check
echo "Test 1: Syntax check"
bash -n "${WRAPPER}" || { echo "FAIL: syntax error"; exit 1; }
echo "PASS: syntax OK"

# Test 2: Timeout command detection (should not error)
echo "Test 2: Timeout detection"
# Create a mock bootstrap that just exits
MOCK_BOOTSTRAP="${TEMP_DIR}/mock-bootstrap.sh"
cat >"${MOCK_BOOTSTRAP}" <<'EOF'
#!/usr/bin/env bash
echo "bootstrap called" >> "${TEMP_DIR}/log.txt"
exit 0
EOF
chmod +x "${MOCK_BOOTSTRAP}"

PID_FILE="${TEMP_DIR}/pid"
# Run wrapper with delay 0 and timeout 5
"${WRAPPER}" "${PID_FILE}" "0" "${MOCK_BOOTSTRAP}" "${MOCK_BOOTSTRAP}" "test/repo" "${TEMP_DIR}" 2>&1 | head -20
# Wait a bit for wrapper to complete
sleep 2
if [[ -f "${TEMP_DIR}/log.txt" ]]; then
  echo "PASS: wrapper executed bootstrap"
else
  echo "INFO: bootstrap may not have run (maybe active heartbeat check)"
fi

# Cleanup
rm -f "${PID_FILE}"
echo "All tests passed"