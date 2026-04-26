#!/usr/bin/env bash
set -euo pipefail

# validate-version.sh - Validate package version before release
# Usage: bash tools/bin/validate-version.sh [--fix]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIX_MODE=false

if [[ "${1:-}" == "--fix" ]]; then
  FIX_MODE=true
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PACKAGE_JSON="${SCRIPT_DIR}/../../package.json"
CHANGELOG="${SCRIPT_DIR}/../../CHANGELOG.md"

errors=0

error() {
  echo -e "${RED}✗ ERROR: $1${NC}"
  ((errors++))
}

warn() {
  echo -e "${YELLOW}⚠ WARNING: $1${NC}"
}

pass() {
  echo -e "${GREEN}✓ PASS: $1${NC}"
}

echo "=== ACP Version Validation ==="
echo ""

# 1. Check package.json exists
if [[ ! -f "$PACKAGE_JSON" ]]; then
  error "package.json not found at $PACKAGE_JSON"
  exit 1
fi

# 2. Extract and validate version format
if ! command -v jq >/dev/null 2>&1; then
  error "jq is required but not installed"
  exit 1
fi

VERSION=$(jq -r '.version' "$PACKAGE_JSON")
if [[ -z "$VERSION" || "$VERSION" == "null" ]]; then
  error "Could not extract version from package.json"
  exit 1
fi

echo "Current version: $VERSION"

# Validate semver format (x.y.z where x,y,z are numbers)
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  error "Version '$VERSION' does not follow semantic versioning (x.y.z)"
else
  pass "Version follows semantic versioning format"
fi

# 3. Check if git tag exists for this version
if command -v git >/dev/null 2>&1; then
  TAG="v$VERSION"
  if git rev-parse "$TAG" >/dev/null 2>&1; then
    warn "Git tag '$TAG' already exists"
    if [[ "$FIX_MODE" == "true" ]]; then
      echo "  Removing existing tag..."
      git tag -d "$TAG" 2>/dev/null
      pass "Removed existing tag '$TAG'"
    fi
  else
    pass "Git tag '$TAG' does not exist yet (good for new release)"
  fi
  
  # Check if there are uncommitted changes
  if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
    warn "There are uncommitted changes in the working directory"
  else
    pass "Working directory is clean"
  fi
fi

# 4. Check CHANGELOG.md for version entry
if [[ -f "$CHANGELOG" ]]; then
  if grep -q "## \[$VERSION\]" "$CHANGELOG" || grep -q "## v$VERSION" "$CHANGELOG"; then
    pass "CHANGELOG.md has entry for version $VERSION"
  else
    error "CHANGELOG.md does not have entry for version $VERSION"
    if [[ "$FIX_MODE" == "true" ]]; then
      echo "  Adding CHANGELOG entry..."
      # Backup
      cp "$CHANGELOG" "${CHANGELOG}.backup"
      # Add new entry after first line
      (head -n 1 "$CHANGELOG" && echo "" && echo "## [$VERSION] - $(date +%Y-%m-%d)" && echo "" && tail -n +2 "$CHANGELOG") > "${CHANGELOG}.tmp"
      mv "${CHANGELOG}.tmp" "$CHANGELOG"
      pass "Added CHANGELOG entry for $VERSION"
    fi
  fi
else
  warn "CHANGELOG.md not found"
fi

# 5. Check engines field
ENGINES_NODE=$(jq -r '.engines.node // empty' "$PACKAGE_JSON")
if [[ -n "$ENGINES_NODE" ]]; then
  pass "engines.node is set: $ENGINES_NODE"
else
  error "engines.node is not set in package.json"
fi

# 6. Check files field
FILES_COUNT=$(jq '.files | length' "$PACKAGE_JSON")
if [[ "$FILES_COUNT" -gt 0 ]]; then
  pass "files field contains $FILES_COUNT entries"
else
  warn "files field is empty - nothing will be included in the package"
fi

# 7. Check for required scripts
for script in "test" "doctor" "smoke"; do
  if jq -e ".scripts.\"$script\"" "$PACKAGE_JSON" >/dev/null 2>&1; then
    pass "script '$script' is defined"
  else
    warn "script '$script' is not defined"
  fi
done

echo ""
echo "=== Summary ==="
if [[ $errors -gt 0 ]]; then
  echo -e "${RED}Validation FAILED with $errors error(s)${NC}"
  exit 1
else
  echo -e "${GREEN}Validation PASSED${NC}"
  exit 0
fi
