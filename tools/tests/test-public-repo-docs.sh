#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

# Check required files exist
test -f "$ROOT_DIR/SECURITY.md"
test -f "$ROOT_DIR/CODE_OF_CONDUCT.md"
test -f "$ROOT_DIR/CHANGELOG.md"
test -f "$ROOT_DIR/ROADMAP.md"
test -f "$ROOT_DIR/references/architecture.md"
test -f "$ROOT_DIR/references/release-checklist.md"
test -f "$ROOT_DIR/.github/release-template.md"
test -f "$ROOT_DIR/.github/workflows/ci.yml"
test -f "$ROOT_DIR/.github/workflows/publish.yml"

# Check basic structure of key files
grep -q 'Use GitHub private vulnerability reporting' "$ROOT_DIR/SECURITY.md"
grep -q 'Code of Conduct' "$ROOT_DIR/CODE_OF_CONDUCT.md"
grep -q '^## \[Unreleased\]$' "$ROOT_DIR/CHANGELOG.md"

# ROADMAP.md checks - verify key sections exist
grep -q '^# Roadmap$' "$ROOT_DIR/ROADMAP.md"
grep -q '^## Current Direction$' "$ROOT_DIR/ROADMAP.md"
grep -q '^## Platform Support$' "$ROOT_DIR/ROADMAP.md"
grep -q '^## Backend Support$' "$ROOT_DIR/ROADMAP.md"
grep -q '^## Product Roadmap$' "$ROOT_DIR/ROADMAP.md"
grep -q 'ROADMAP STATUS.*COMPLETE' "$ROOT_DIR/ROADMAP.md"

# README.md checks - verify key sections and badges exist
grep -q 'keeps your coding agents running reliably' "$ROOT_DIR/README.md"
grep -q 'SECURITY.md' "$ROOT_DIR/README.md"
grep -q 'CODE_OF_CONDUCT.md' "$ROOT_DIR/README.md"
grep -q 'CHANGELOG.md' "$ROOT_DIR/README.md"
grep -q 'ROADMAP.md' "$ROOT_DIR/README.md"
grep -q 'badge' "$ROOT_DIR/README.md"
grep -q 'npmjs.com' "$ROOT_DIR/README.md"

# Check publish workflow has required fields
grep -q 'name: Publish$' "$ROOT_DIR/.github/workflows/publish.yml"
grep -q 'id-token: write' "$ROOT_DIR/.github/workflows/publish.yml"
grep -q 'npm publish' "$ROOT_DIR/.github/workflows/publish.yml"
grep -q 'git describe --tags --exact-match' "$ROOT_DIR/.github/workflows/publish.yml"

# Check release template and checklist exist and have key content
grep -q 'Release Summary' "$ROOT_DIR/.github/release-template.md"
grep -q 'trusted publishing' "$ROOT_DIR/references/release-checklist.md"

echo "public repo docs test passed"
