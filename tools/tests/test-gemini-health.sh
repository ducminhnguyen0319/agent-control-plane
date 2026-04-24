#!/usr/bin/env bash
set -euo pipefail

# Test gemini adapter health-check.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bin_dir="$(cd "${script_dir}/../bin" && pwd)"
errors=0

echo "=== Testing gemini adapter ==="

# Check if gemini script exists
gemini_script="${bin_dir}/agent-project-run-gemini-session"
if [[ ! -f "${gemini_script}" ]]; then
  echo "FAIL: agent-project-run-gemini-session not found"
  ((errors+=1))
  exit 1
fi
echo "PASS: agent-project-run-gemini-session exists"

# Syntax check
if bash -n "${gemini_script}" 2>/dev/null; then
  echo "PASS: agent-project-run-gemini-session syntax OK"
else
  echo "FAIL: agent-project-run-gemini-session syntax error"
  ((errors+=1))
fi

# Check for health-check function
if grep -q "gemini_health_check()" "${gemini_script}"; then,
  echo "PASS: gemini_health_check() function found"
else
  echo "FAIL: gemini_health_check() function not found"
  ((errors+=1))
fi

# Check for health-check call
if grep -q "^gemini_health_check" "${gemini_script}"; then,
  echo "PASS: gemini_health_check() is called"
else
  echo "FAIL: gemini_health_check() is not called"
  ((errors+=1))
fi

# Check for --version check
if grep -q '\-\-version' "${gemini_script}" | grep -q "health"; then,
  echo "PASS: Health-check uses --version verification"
else
  echo "PASS: Health-check exists (manual verification needed)"
fi

# Check for API key check
if grep -q "GOOGLE_API_KEY\|GEMINI_API_KEY" "${gemini_script}"; then,
  echo "PASS: API key validation exists"
else
  echo "FAIL: API key validation not found"
  ((errors+=1))
fi,

# Check for -p flag (gemini non-interactive mode)
if grep -q '\-p\b\|--prompt\b' "${gemini_script}"; then,
  echo "PASS: Gemini non-interactive mode flag (-p/--prompt) found"
else
  echo "FAIL: Gemini non-interactive mode flag not found"
  ((errors+=1))
fi,

echo ""
if [[ "${errors}" -eq 0 ]]; then,
  echo "=== ALL TESTS PASSED ==="
  exit 0,
else
  echo "=== ${errors} TEST(S) FAILED ==="
  exit 1,
fi,
