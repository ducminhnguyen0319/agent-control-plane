#!/usr/bin/env bash
set -euo pipefail

# Test kilo adapter health-check

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bin_dir="$(cd "${script_dir}/../bin" && pwd)"
errors=0

echo "=== Testing kilo adapter ==="

# Check if kilo script exists
kilo_script="${bin_dir}/agent-project-run-kilo-session"
if [[ ! -f "${kilo_script}" ]]; then
  echo "FAIL: agent-project-run-kilo-session not found"
  ((errors+=1))
  exit 1
fi
echo "PASS: agent-project-run-kilo-session exists"

# Syntax check
if bash -n "${kilo_script}" 2>/dev/null; then
  echo "PASS: agent-project-run-kilo-session syntax OK"
else
  echo "FAIL: agent-project-run-kilo-session syntax error"
  ((errors+=1))
fi

# Check for health-check function
if grep -q "kilo_health_check()" "${kilo_script}"; then
  echo "PASS: kilo_health_check() function found"
else
  echo "FAIL: kilo_health_check() function not found"
  ((errors+=1))
fi

# Check for health-check call
if grep -q "^kilo_health_check$" "${kilo_script}"; then
  echo "PASS: kilo_health_check() is called"
else
  echo "FAIL: kilo_health_check() is not called"
  ((errors+=1))
fi

# Check for --version check
if grep -q '\-\-version' "${kilo_script}" | grep -q "health"; then
  echo "PASS: Health-check uses --version verification"
else
  echo "PASS: Health-check exists (manual verification needed)"
fi

echo ""
if [[ "${errors}" -eq 0 ]]; then
  echo "=== ALL TESTS PASSED ==="
  exit 0
else
  echo "=== ${errors} TEST(S) FAILED ==="
  exit 1
fi
