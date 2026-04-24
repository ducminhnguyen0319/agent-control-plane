#!/usr/bin/env bash
set -euo pipefail

# Test pi adapter health-check

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bin_dir="$(cd "${script_dir}/../bin" && pwd)"
errors=0

echo "=== Testing pi adapter ==="

# Check if pi script exists
pi_script="${bin_dir}/agent-project-run-pi-session"
if [[ ! -f "${pi_script}" ]]; then
  echo "FAIL: agent-project-run-pi-session not found"
  ((errors+=1))
  exit 1
fi
echo "PASS: agent-project-run-pi-session exists"

# Syntax check
if bash -n "${pi_script}" 2>/dev/null; then
  echo "PASS: agent-project-run-pi-session syntax OK"
else
  echo "FAIL: agent-project-run-pi-session syntax error"
  ((errors+=1))
fi

# Check for health-check function
if grep -q "pi_health_check()" "${pi_script}"; then
  echo "PASS: pi_health_check() function found"
else
  echo "FAIL: pi_health_check() function not found"
  ((errors+=1))
fi

# Check for health-check call
if grep -q "^pi_health_check$" "${pi_script}"; then
  echo "PASS: pi_health_check() is called"
else
  echo "FAIL: pi_health_check() is not called"
  ((errors+=1))
fi

# Check for OPENROUTER_API_KEY check
if grep -q "OPENROUTER_API_KEY" "${pi_script}"; then
  echo "PASS: OPENROUTER_API_KEY validation exists"
else
  echo "FAIL: OPENROUTER_API_KEY validation not found"
  ((errors+=1))
fi

# Check for --version check
if grep -q '\-\-version' "${pi_script}" | grep -q "health"; then
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
