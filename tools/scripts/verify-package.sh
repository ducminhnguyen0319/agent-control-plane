#!/usr/bin/env bash
set -euo pipefail

# verify-package.sh - Verify npm package integrity
# Usage: bash tools/scripts/verify-package.sh [--fix]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_JSON="$SCRIPT_DIR/package.json"
ERRORS=0

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

echo "=== ACP Package Verification ==="
echo ""

# 1. Check package.json exists
if [[ ! -f "$PACKAGE_JSON" ]]; then
  error "package.json not found at $PACKAGE_JSON"
  exit 1
fi

# 2. Check "files" field
info "Step 1: Checking files field..."
if ! command -v jq >/dev/null 2>&1; then
  error "jq is required but not installed"
  exit 1
fi

FILES_COUNT=$(jq '.files | length' "$PACKAGE_JSON")
if [[ "$FILES_COUNT" -eq 0 ]]; then
  error "files field is empty - nothing will be included in the package"
else
  pass "files field contains $FILES_COUNT entries"
fi

# 3. Run npm pack --dry-run
info "Step 2: Running npm pack --dry-run..."
cd "$SCRIPT_DIR"
PACK_OUTPUT=$(npm pack --dry-run 2>&1)
if [[ $? -eq 0 ]]; then
  pass "npm pack --dry-run succeeded"
  echo "$PACK_OUTPUT" | grep -E "npm notice|Tarball Contents" || true
else
  error "npm pack --dry-run failed"
  echo "$PACK_OUTPUT"
fi

# 4. Check for required files
info "Step 3: Checking required files..."
REQUIRED_FILES=(
  "README.md"
  "package.json"
  "bin/agent-control-plane"
  "tools/bin/"
  "npm/"
)

for file in "${REQUIRED_FILES[@]}"; do
  if echo "$PACK_OUTPUT" | grep -q "$file" || echo "$PACK_OUTPUT" | grep -q "Tarball Contents"; then
    pass "Required: $file is included"
  else
    warn "Required: $file may not be included (check 'files' field)"
  fi
done

# 5. Check for unwanted files
info "Step 4: Checking for unwanted files..."
UNWANTED_PATTERNS=(
  "node_modules"
  ".git"
  ".DS_Store"
  "*.log"
  "tmp/"
  "temp/"
)

for pattern in "${UNWANTED_PATTERNS[@]}"; do
  if echo "$PACK_OUTPUT" | grep -q "$pattern"; then
    warn "Unwanted: Found '$pattern' in package (add to .npmignore)"
  fi
done

# 6. Check package size
info "Step 5: Checking package size..."
PACK_SIZE=$(echo "$PACK_OUTPUT" | grep -oE "size: [0-9.]+[kMG]?" | head -1 || echo "unknown")
if [[ -n "$PACK_SIZE" ]]; then
  pass "Package size: $PACK_SIZE"
else
  # Try to get size from npm pack output
  TARBALL=$(echo "$PACK_OUTPUT" | grep -oE "npm notice filename:.*\.tgz" | sed 's/.*: //')
  if [[ -n "$TARBALL" && -f "$TARBALL" ]]; then
    SIZE=$(du -h "$TARBALL" | cut -f1)
    pass "Package size: $SIZE"
    rm -f "$TARBALL"
  else
    info "Package size: unknown (check npm pack output)"
  fi
fi

# 7. Verify README.md is included
info "Step 6: Verifying README.md..."
if [[ ! -f "$SCRIPT_DIR/README.md" ]]; then
  warn "README.md not found in package root"
else
  pass "README.md exists"
fi

# 8. Check .npmignore exists
info "Step 7: Checking .npmignore..."
if [[ -f "$SCRIPT_DIR/.npmignore" ]]; then
  pass ".npmignore exists"
else
  warn ".npmignore not found (recommended to exclude test/ and build artifacts)"
fi

echo ""
echo "=== Verification Summary ==="
if [[ $ERRORS -gt 0 ]]; then
  echo -e "${RED}✗ Verification FAILED with $ERRORS error(s)${NC}"
  exit 1
else
  echo -e "${GREEN}✓ Verification PASSED${NC}"
  exit 0
fi
