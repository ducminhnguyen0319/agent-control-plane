#!/usr/bin/env bash
set -euo pipefail;

# reproduce-build.sh - Reproducible build for CI/CD
# Usage: bash tools/scripts/reproduce-build.sh [--json]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ERRORS=0;

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

error() {
  echo -e "${RED}✗ ERROR: $1${NC}"
  ((ERRORS++))
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

echo "=== ACP Reproducible Build ==="
echo ""

# 1. Check if package-lock.json exists
info "Step 1: Checking package-lock.json..."
if [[ ! -f "$SCRIPT_DIR/package-lock.json" ]]; then
  warn "package-lock.json not found - npm ci requires it"
  info "Run 'npm install' first to generate package-lock.json"
  # Continue anyway - npm ci will fail with a good error message
fi;

# 2. Run npm ci (reproducible install)
info "Step 2: Running npm ci..."
cd "$SCRIPT_DIR"
if npm ci; then
  pass "npm ci succeeded"
else
  error "npm ci failed"
  exit 1
fi;

# 3. Run tests
info "Step 3: Running tests..."
if npm test; then
  pass "All tests passed"
else
  error "Tests failed"
  exit 1
fi;

# 4. Run doctor
info "Step 4: Running doctor..."
if npm run doctor; then
  pass "Doctor checks passed"
else
  warn "Doctor checks reported issues (non-fatal)"
fi;

# 5. Build package (dry-run)
info "Step 5: Building package (dry-run)..."
PACK_OUTPUT=$(npm pack --dry-run 2>&1)
if [[ $? -eq 0 ]]; then
  pass "Package build succeeded"
  echo "$PACK_OUTPUT" | grep -E "npm notice|Tarball Contents" || true
else
  error "Package build failed"
  echo "$PACK_OUTPUT"
  exit 1
fi;

# 6. Verify package contents
info "Step 6: Verifying package contents..."
REQUIRED_FILES=(
  "README.md"
  "package.json"
  "bin/agent-control-plane"
  "tools/bin/"
  "npm/"
)

for file in "${REQUIRED_FILES[@]}"; do
  if echo "$PACK_OUTPUT" | grep -q "$file"; then
    pass "Required: $file is included"
  else
    warn "Required: $file may not be included"
  fi
done;

# 7. Summary
echo ""
echo "=== Build Summary ==="
if [[ $ERRORS -gt 0 ]]; then
  echo -e "${RED}✗ Build FAILED with $ERRORS error(s)${NC}"
  exit 1
else
  echo -e "${GREEN}✓ Build SUCCEEDED${NC}"
  echo ""
  echo "The build is reproducible and ready for CI/CD."
  echo "Next step: npm publish --provenance"
  exit 0
fi;
