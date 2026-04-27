#!/usr/bin/env bash
set -euo pipefail

# security-scan.sh - Security vulnerability scan
# Usage: bash tools/scripts/security-scan.sh [--fix] [--json]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PACKAGE_JSON="$SCRIPT_DIR/package.json"
FIX_MODE=false
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fix)
      FIX_MODE=true
      shift
      ;;
    --json)
      JSON_OUTPUT=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

error() {
  echo -e "${RED}✗ ERROR: $1${NC}"
}

warn() {
  echo -e "${YELLOW}⚠ WARNING: $1${NC}"
}

pass() {
  echo -e "${GREEN}✓ PASS: $1${NC}"
}

info() {
  echo -e "${BLUE}ℹ INFO: $1${NC}"
}

echo "=== ACP Security Scan ==="
echo ""

# 1. Check if npm audit is available
info "Step 1: Checking npm audit availability..."
if ! command -v npm >/dev/null 2>&1; then
  error "npm is not installed"
  exit 1
fi

# 2. Run npm audit
info "Step 2: Running npm audit..."
AUDIT_OUTPUT=$(cd "$SCRIPT_DIR" && npm audit --json 2>&1 || true)
AUDIT_EXIT_CODE=$?

if [[ "$JSON_OUTPUT" == "true" ]]; then
  echo "$AUDIT_OUTPUT"
  exit $AUDIT_EXIT_CODE
fi

# 3. Parse and display results
info "Step 3: Parsing audit results..."

if [[ $AUDIT_EXIT_CODE -eq 0 ]]; then
  pass "No vulnerabilities found!"
  echo ""
  echo "=== Scan Summary ==="
  echo -e "${GREEN}✓ No vulnerabilities detected${NC}"
  exit 0
fi

# Parse vulnerability counts
if command -v jq >/dev/null 2>&1; then
  VULN_COUNT=$(echo "$AUDIT_OUTPUT" | jq -r '.metadata.vulnerabilities.total // 0' 2>/dev/null || echo "0")
  CRITICAL=$(echo "$AUDIT_OUTPUT" | jq -r '.metadata.vulnerabilities.critical // 0' 2>/dev/null || echo "0")
  HIGH=$(echo "$AUDIT_OUTPUT" | jq -r '.metadata.vulnerabilities.high // 0' 2>/dev/null || echo "0")
  MODERATE=$(echo "$AUDIT_OUTPUT" | jq -r '.metadata.vulnerabilities.moderate // 0' 2>/dev/null || echo "0")
  LOW=$(echo "$AUDIT_OUTPUT" | jq -r '.metadata.vulnerabilities.low // 0' 2>/dev/null || echo "0")
else
  VULN_COUNT=$(echo "$AUDIT_OUTPUT" | grep -c "vulnerabilities" || echo "0")
  CRITICAL=0
  HIGH=0
  MODERATE=0
  LOW=0
fi

echo ""
echo "=== Vulnerability Summary ==="
echo "Total: $VULN_COUNT"
echo -e "${RED}Critical: $CRITICAL${NC}"
echo -e "${RED}High: $HIGH${NC}"
echo -e "${YELLOW}Moderate: $MODERATE${NC}"
echo -e "${GREEN}Low: $LOW${NC}"
echo ""

# 4. Show details for critical/high
if [[ $CRITICAL -gt 0 || $HIGH -gt 0 ]]; then
  warn "Critical/High vulnerabilities found!"
  echo ""
  echo "Details:"
  if command -v jq >/dev/null 2>&1; then
    echo "$AUDIT_OUTPUT" | jq -r '.vulnerabilities | to_entries[] | select(.value.severity == "critical" or .value.severity == "high") | "  - \(.key): \(.value.severity) - \(.value.title)"' 2>/dev/null || true
  fi
fi

# 5. Offer fix
if [[ $VULN_COUNT -gt 0 ]]; then
  echo ""
  if [[ "$FIX_MODE" == "true" ]]; then
    info "Step 4: Attempting to fix vulnerabilities..."
    cd "$SCRIPT_DIR" && npm audit fix
    pass "npm audit fix completed"
  else
    warn "Vulnerabilities found!"
    echo ""
    echo "To fix automatically, run:"
    echo "  bash tools/scripts/security-scan.sh --fix"
    echo ""
    echo "Or manually:"
    echo "  cd $SCRIPT_DIR"
    echo "  npm audit fix"
    echo "  npm update"
  fi
fi

# 6. Check for outdated dependencies (security-relevant)
info "Step 5: Checking for outdated dependencies..."
if command -v jq >/dev/null 2>&1; then
  OUTDATED=$(cd "$SCRIPT_DIR" && npm outdated --json 2>/dev/null || true)
  if [[ -n "$OUTDATED" && "$OUTDATED" != "{}" ]]; then
    warn "Outdated dependencies found:"
    echo "$OUTDATED" | jq -r 'to_entries[] | "  - \(.key): \(.value.current) -> \(.value.latest)"' 2>/dev/null || true
  else
    pass "All dependencies are up to date"
  fi
fi

# 7. Summary
echo ""
echo "=== Scan Summary ==="
if [[ $VULN_COUNT -gt 0 ]]; then
  if [[ $CRITICAL -gt 0 || $HIGH -gt 0 ]]; then
    echo -e "${RED}✗ Security issues found ($VULN_COUNT vulnerabilities)${NC}"
    exit 1
  else
    echo -e "${YELLOW}⚠ Minor vulnerabilities found ($VULN_COUNT)${NC}"
    exit 0
  fi
else
  echo -e "${GREEN}✓ No vulnerabilities detected${NC}"
  exit 0
fi
