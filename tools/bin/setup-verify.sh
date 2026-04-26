#!/usr/bin/env bash
set -euo pipefail

# setup-verify.sh - Verify ACP setup and environment
# Usage: bash tools/bin/setup-verify.sh [--profile-id <id>]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLOW_TOOLS_DIR="${SCRIPT_DIR}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASSED=0
FAILED=0
WARNINGS=0

pass() {
  echo -e "${GREEN}✓ PASS${NC}: $1"
  ((PASSED++))
}

fail() {
  echo -e "${RED}✗ FAIL${NC}: $1"
  ((FAILED++))
}

warn() {
  echo -e "${YELLOW}⚠ WARN${NC}: $1"
  ((WARNINGS++))
}

echo "=== ACP Setup Verification ==="
echo ""

# 1. Check required dependencies
echo "--- Dependencies ---"
for cmd in node bash git jq python3 tmux; do
  if command -v "$cmd" >/dev/null 2>&1; then
    pass "$cmd is installed"
  else
    fail "$cmd is NOT installed"
  fi
done

# Check Node.js version
if command -v node >/dev/null 2>&1; then
  NODE_VERSION=$(node -v | sed 's/^v//' | cut -d. -f1)
  if [[ "$NODE_VERSION" -ge 18 ]]; then
    pass "Node.js version >= 18 ($(node -v))"
  else
    fail "Node.js version < 18 ($(node -v))"
  fi
fi

# Check gh CLI (for GitHub setups)
if command -v gh >/dev/null 2>&1; then
  pass "gh CLI is installed"
  if gh auth status &>/dev/null; then
    pass "gh CLI is authenticated"
  else
    warn "gh CLI is NOT authenticated (run: gh auth login)"
  fi
else
  warn "gh CLI not installed (needed for GitHub setups)"
fi

echo ""
echo "--- Runtime Directories ---"
for dir in ~/.agent-runtime ~/.agent-runtime/control-plane ~/.agent-runtime/runtime-home; do
  if [[ -d "$dir" ]]; then
    pass "$dir exists"
  else
    warn "$dir does NOT exist (will be created on first run)"
  fi
done

echo ""
echo "--- Profile Check ---"
PROFILE_ID="${1:-}"
if [[ -n "$PROFILE_ID" ]]; then
  PROFILE_DIR="$HOME/.agent-runtime/control-plane/profiles/$PROFILE_ID"
  if [[ -d "$PROFILE_DIR" ]]; then
    pass "Profile '$PROFILE_ID' exists at $PROFILE_DIR"
    
    # Check control-plane.yaml
    if [[ -f "$PROFILE_DIR/control-plane.yaml" ]]; then
      pass "control-plane.yaml exists"
    else
      fail "control-plane.yaml NOT found"
    fi
    
    # Check runtime.env
    if [[ -f "$PROFILE_DIR/runtime.env" ]]; then
      pass "runtime.env exists"
    else
      warn "runtime.env NOT found"
    fi
  else
    warn "Profile '$PROFILE_ID' does NOT exist"
  fi
else
  warn "No profile ID provided - skipping profile checks"
  echo "  Usage: bash tools/bin/setup-verify.sh --profile-id <id>"
fi

echo ""
echo "--- Worker Backend ---"
# Check for common worker backends
for backend in codex claude ollama pi opencode kilo; do
  case "$backend" in
    codex)
      if command -v codex >/dev/null 2>&1; then
        pass "codex backend available"
      else
        warn "codex backend NOT found"
      fi
      ;;
    claude)
      if command -v claude >/dev/null 2>&1; then
        pass "claude backend available"
      else
        warn "claude backend NOT found"
      fi
      ;;
    ollama)
      if command -v ollama >/dev/null 2>&1; then
        pass "ollama backend available"
        # Check if ollama server is running
        if curl -s http://localhost:11434/api/tags >/dev/null 2>&1; then
          pass "ollama server is running"
        else
          warn "ollama server is NOT running (start with: ollama serve)"
        fi
      else
        warn "ollama backend NOT found"
      fi
      ;;
    pi)
      if command -v pi >/dev/null 2>&1 || npm list -g @mariozechner/pi-coding-agent >/dev/null 2>&1; then
        pass "pi backend available"
      else
        warn "pi backend NOT found"
      fi
      ;;
    opencode)
      if command -v opencode >/dev/null 2>&1; then
        pass "opencode backend available"
      else
        warn "opencode backend NOT found"
      fi
      ;;
    kilo)
      if command -v kilo >/dev/null 2>&1 || npm list -g @kilocode/cli >/dev/null 2>&1; then
        pass "kilo backend available"
      else
        warn "kilo backend NOT found"
      fi
      ;;
  esac
done

echo ""
echo "=== Summary ==="
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
echo -e "${YELLOW}Warnings: $WARNINGS${NC}"

if [[ $FAILED -gt 0 ]]; then
  echo ""
  echo -e "${RED}Setup verification FAILED${NC}"
  exit 1
else
  echo ""
  echo -e "${GREEN}Setup verification PASSED${NC}"
  exit 0
fi
