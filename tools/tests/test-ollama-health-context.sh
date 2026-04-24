#!/usr/bin/env bash
set -euo pipefail

# Test ollama adapter health-check and context detection

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
errors=0

echo "=== Testing ollama adapter ==="

# Check if ollama script exists
ollama_script="${script_dir}/../bin/agent-project-run-ollama-session"
if [[ ! -f "${ollama_script}" ]]; then
  echo "FAIL: agent-project-run-ollama-session not found"
  ((errors+=1))
  exit 1
fi
echo "PASS: agent-project-run-ollama-session exists"

# Syntax check
if bash -n "${ollama_script}" 2>/dev/null; then
  echo "PASS: agent-project-run-ollama-session syntax OK"
else
  echo "FAIL: agent-project-run-ollama-session syntax error"
  ((errors+=1))
fi

# Check for health-check function
if grep -q "ollama_health_check()" "${ollama_script}"; then
  echo "PASS: ollama_health_check() function found"
else
  echo "FAIL: ollama_health_check() function not found"
  ((errors+=1))
fi

# Check for health-check call
if grep -q "ollama_health_check$" "${ollama_script}"; then
  echo "PASS: ollama_health_check() is called"
else
  echo "FAIL: ollama_health_check() is not called"
  ((errors+=1))
fi

# Check for curl health-check with /api/tags
if grep -q "curl.*api/tags" "${ollama_script}"; then
  echo "PASS: Health-check uses /api/tags endpoint"
else
  echo "FAIL: Health-check missing /api/tags endpoint"
  ((errors+=1))
fi

# Check for context detection function in Node.js code
if grep -q "async function detectContextWindow()" "${ollama_script}"; then
  echo "PASS: detectContextWindow() function found"
else
  echo "FAIL: detectContextWindow() function not found"
  ((errors+=1))
fi

# Check for contextWindow variable usage
if grep -q "const contextWindow = await detectContextWindow()" "${ollama_script}"; then
  echo "PASS: contextWindow is properly initialized"
else
  echo "FAIL: contextWindow initialization not found"
  ((errors+=1))
fi

# Check for num_ctx: contextWindow (not hardcoded)
if grep -q "num_ctx: contextWindow" "${ollama_script}"; then
  echo "PASS: ollamaChat uses dynamic contextWindow"
else
  echo "FAIL: ollamaChat still uses hardcoded num_ctx"
  ((errors+=1))
fi

# Check for /api/show call for context detection
if grep -q "api/show" "${ollama_script}"; then
  echo "PASS: Context detection uses /api/show endpoint"
else
  echo "FAIL: Context detection missing /api/show endpoint"
  ((errors+=1))
fi

# Check for model_info context_length parsing
if grep -q "llama.context_length" "${ollama_script}"; then
  echo "PASS: Context window parsing from model_info"
else
  echo "FAIL: Context window parsing not found"
  ((errors+=1))
fi

echo ""
if [[ "${errors}" -eq 0 ]]; then
  echo "=== ALL TESTS PASSED ==="
  exit 0
else
  echo "=== ${errors} TEST(S) FAILED ==="
  exit 1
fi
