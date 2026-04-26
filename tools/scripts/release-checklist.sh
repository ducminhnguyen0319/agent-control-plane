#!/usr/bin/env bash
set -euo pipefail

# release-checklist.sh - Automated release checklist
# Usage: bash tools/scripts/release-checklist.sh [--version <x.y.z>] [--no-tag]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_JSON="$SCRIPT_DIR/package.json"
CHANGELOG="$SCRIPT_DIR/CHANGELOG.md"
VERSION=""
NO_TAG=false
ERRORS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="$2"
      shift 2
      ;;
    --no-tag)
      NO_TAG=true
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

echo "=== ACP Release Checklist ==="
echo ""

# 1. Check current version
info "Step 1: Checking current version..."
if ! command -v jq >/dev/null 2>&1; then
  error "jq is required but not installed"
  exit 1
fi

CURRENT_VERSION=$(jq -r '.version' "$PACKAGE_JSON" 2>/dev/null)
if [[ -z "$CURRENT_VERSION" || "$CURRENT_VERSION" == "null" ]]; then
  error "Could not extract version from package.json"
  exit 1
fi

pass "Current version: $CURRENT_VERSION"

# Use provided version or prompt
if [[ -z "$VERSION" ]]; then
  read -p "Enter version to release (current: $CURRENT_VERSION): " VERSION
fi

if [[ -z "$VERSION" ]]; then
  VERSION="$CURRENT_VERSION"
fi

info "Releasing version: $VERSION"

# 2. Validate version format
info "Step 2: Validating version format..."
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  error "Version '$VERSION' does not follow semantic versioning (x.y.z)"
  exit 1
fi
pass "Version format is valid (semver)"

# 3. Update version in package.json if different
if [[ "$VERSION" != "$CURRENT_VERSION" ]]; then
  info "Step 3: Updating version in package.json..."
  jq ".version = \"$VERSION\"" "$PACKAGE_JSON" > "${PACKAGE_JSON}.tmp"
  mv "${PACKAGE_JSON}.tmp" "$PACKAGE_JSON"
  pass "Updated package.json to version $VERSION"
else
  pass "Version unchanged: $VERSION"
fi

# 4. Check CHANGELOG
info "Step 4: Checking CHANGELOG.md..."
if [[ ! -f "$CHANGELOG" ]]; then
  warn "CHANGELOG.md not found"
else
  if grep -q "## \[$VERSION\]" "$CHANGELOG" || grep -q "## v$VERSION" "$CHANGELOG"; then
    pass "CHANGELOG.md has entry for version $VERSION"
  else
    error "CHANGELOG.md does not have entry for version $VERSION"
  fi
fi

# 5. Run tests
info "Step 5: Running tests..."
if npm test; then
  pass "All tests passed"
else
  error "Tests failed"
fi

# 6. Run doctor
info "Step 6: Running doctor..."
if npm run doctor; then
  pass "Doctor checks passed"
else
  warn "Doctor checks reported issues (non-fatal)"
fi

# 7. Validate package
info "Step 7: Validating package..."
if bash tools/bin/validate-version.sh; then
  pass "Package validation passed"
else
  error "Package validation failed"
fi

# 8. Build package (dry run)
info "Step 8: Building package (dry run)..."
if npm publish --dry-run 2>&1 | tee /tmp/acp-publish-dry-run.log; then
  pass "Dry run published successfully"
  info "Check /tmp/acp-publish-dry-run.log for package contents"
else
  error "Dry run failed"
fi

# 9. Check git status
info "Step 9: Checking git status..."
if command -v git >/dev/null 2>&1; then
  if [[ -n "$(git -C "$SCRIPT_DIR" status --porcelain 2>/dev/null)" ]]; then
    warn "There are uncommitted changes"
    echo "  Run: git -C $SCRIPT_DIR status"
  else
    pass "Working directory is clean"
  fi
  
  # Check if tag exists
  TAG="v$VERSION"
  if git -C "$SCRIPT_DIR" rev-parse "$TAG" >/dev/null 2>&1; then
    warn "Git tag '$TAG' already exists"
  else
    pass "Git tag '$TAG' does not exist yet"
  fi
fi

# 10. Summary
echo ""
echo "=== Release Checklist Summary ==="
if [[ $ERRORS -gt 0 ]]; then
  echo -e "${RED}✗ Release NOT ready ($ERRORS error(s))${NC}"
  echo ""
  echo "Fix the errors above and run again."
  exit 1
else
  echo -e "${GREEN}✓ Release is ready!${NC}"
  echo ""
  echo "Next steps:"
  echo "  1. Commit changes: git add package.json CHANGELOG.md && git commit -m 'chore: release v$VERSION'"
  echo "  2. Push: git push origin main"
  if [[ "$NO_TAG" == "false" ]]; then
    echo "  3. Create tag: git tag v$VERSION && git push origin v$VERSION"
  fi
  echo "  4. Publish: npm publish --provenance"
  echo ""
  echo "Or run all at once:"
  echo "  git add package.json CHANGELOG.md && \\"
  echo "  git commit -m 'chore: release v$VERSION' && \\"
  echo "  git push origin main && \\"
  if [[ "$NO_TAG" == "false" ]]; then
    echo "  git tag v$VERSION && \\"
    echo "  git push origin v$VERSION && \\"
  fi
  echo "  npm publish --provenance"
fi
