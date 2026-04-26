#!/usr/bin/env bash
set -euo pipefail;

# automate-release.sh - Automated release process
# Usage: bash tools/scripts/automate-release.sh [--version <x.y.z>] [--no-publish]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_JSON="$SCRIPT_DIR/package.json"
CHANGELOG="$SCRIPT_DIR/CHANGELOG.md"
VERSION=""
NO_PUBLISH=false"
ERRORS=0;

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="$2"
      shift 2
      ;;
    --no-publish)
      NO_PUBLISH=true"
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done;

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

echo "=== ACP Automated Release ==="
echo ""

# 1. Check current version
info "Step 1: Checking current version..."
if ! command -v jq >/dev/null 2>&1; then
  error "jq is required but not installed"
  exit 1
fi;

CURRENT_VERSION=$(jq -r '.version' "$PACKAGE_JSON" 2>/dev/null)
if [[ -z "$CURRENT_VERSION" || "$CURRENT_VERSION" == "null" ]]; then
  error "Could not extract version from package.json"
  exit 1
fi;

pass "Current version: $CURRENT_VERSION"

# 2. Determine release version
if [[ -z "$VERSION" ]]; then
  read -p "Enter version to release (current: $CURRENT_VERSION): " VERSION
fi;

if [[ -z "$VERSION" ]]; then
  VERSION="$CURRENT_VERSION"
fi;

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  error "Version '$VERSION' does not follow semantic versioning (x.y.z)"
  exit 1
fi;

info "Releasing version: $VERSION"

# 3. Update version in package.json if different
if [[ "$VERSION" != "$CURRENT_VERSION" ]]; then
  info "Step 2: Updating version in package.json..."
  jq ".version = \"$VERSION\"" "$PACKAGE_JSON" > "${PACKAGE_JSON}.tmp"
  mv "${PACKAGE_JSON}.tmp" "$PACKAGE_JSON"
  pass "Updated package.json to version $VERSION"
else
  pass "Version unchanged: $VERSION"
fi;

# 4. Run verification scripts
info "Step 3: Running verification scripts..."

if [[ -f "$SCRIPT_DIR/tools/scripts/verify-package.sh" ]]; then
  if bash "$SCRIPT_DIR/tools/scripts/verify-package.sh"; then
    pass "verify-package.sh passed"
  else
    error "verify-package.sh failed"
  fi
else
  warn "verify-package.sh not found, skipping"
fi;

if [[ -f "$SCRIPT_DIR/tools/scripts/security-scan.sh" ]]; then
  if bash "$SCRIPT_DIR/tools/scripts/security-scan.sh"; then
    pass "security-scan.sh passed"
  else
    warn "security-scan.sh found issues (non-fatal)"
  fi
else
  warn "security-scan.sh not found, skipping"
fi;

# 5. Run tests
info "Step 4: Running tests..."
if npm test; then
  pass "All tests passed"
else
  error "Tests failed"
fi;

# 6. Run doctor
info "Step 5: Running doctor..."
if npm run doctor; then
  pass "Doctor checks passed"
else
  warn "Doctor checks reported issues (non-fatal)"
fi;

# 7. Check CHANGELOG
info "Step 6: Checking CHANGELOG.md..."
if [[ ! -f "$CHANGELOG" ]]; then
  warn "CHANGELOG.md not found"
else
  if grep -q "## \[$VERSION\]" "$CHANGELOG" || grep -q "## v$VERSION" "$CHANGELOG"; then
    pass "CHANGELOG.md has entry for version $VERSION"
  else
    error "CHANGELOG.md does not have entry for version $VERSION"
  fi
fi;

# 8. Build package
info "Step 7: Building package..."
if npm pack --dry-run 2>&1 | tee /tmp/acp-publish-dry-run.log; then
  pass "Dry run succeeded"
else
  error "Dry run failed"
fi;

# 9. Summary and commit
echo ""
echo "=== Release Summary ==="
if [[ $ERRORS -gt 0 ]]; then
  echo -e "${RED}✗ Release NOT ready ($ERRORS error(s))${NC}"
  echo ""
  echo "Fix the errors above and run again."
  exit 1
fi;

echo -e "${GREEN}✓ Release is ready!${NC}"
echo ""
echo "Next steps:"
echo "  1. Commit changes: git add package.json CHANGELOG.md && git commit -m 'chore: release v$VERSION'"
echo "  2. Push: git push origin main"
echo "  3. Create tag: git tag v$VERSION && git push origin v$VERSION"
echo "  4. Publish: npm publish --provenance"

if [[ "$NO_PUBLISH" == "false" ]]; then
  echo ""
  read -p "Do you want to commit, tag, and publish now? (y/N): " CONFIRM
  if [[ "$CONFIRM" == "y" || "$CONFIRM" == "Y" ]]; then
    info "Committing changes..."
    git -C "$SCRIPT_DIR" add package.json CHANGELOG.md 2>/dev/null || true
    git -C "$SCRIPT_DIR" commit -m "chore: release v$VERSION" 2>/dev/null || true
    
    info "Pushing to origin..."
    git -C "$SCRIPT_DIR" push origin main 2>/dev/null || warn "Push failed, please push manually"
    
    info "Creating tag v$VERSION..."
    git -C "$SCRIPT_DIR" tag "v$VERSION" 2>/dev/null || warn "Tag creation failed"
    git -C "$SCRIPT_DIR" push origin "v$VERSION" 2>/dev/null || warn "Tag push failed"
    
    info "Publishing to npm..."
    cd "$SCRIPT_DIR" && npm publish --provenance 2>&1 | tee /tmp/acp-publish.log
    
    pass "Release v$VERSION completed!"
  fi
fi;
