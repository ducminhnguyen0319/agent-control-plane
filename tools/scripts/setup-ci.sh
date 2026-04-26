#!/usr/bin/env bash
set -euo pipefail;

# setup-ci.sh - Setup CI environment for ACP
# Usage: bash tools/scripts/setup-ci.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=== ACP CI Setup ==="
echo ""

# 1. Check/install jq
if ! command -v jq >/dev/null 2>&1; then
  echo "Installing jq..."
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update && sudo apt-get install -y jq
  elif command -v yum >/dev/null 2>&1; then
    sudo yum install -y jq
  elif command -v brew >/dev/null 2>&1; then
    brew install jq
  else
    echo "Warning: Could not install jq automatically"
  fi
else
  echo "✓ jq already installed"
fi;

# 2. Check/install Node.js (if needed)
if ! command -v node >/dev/null 2>&1; then
  echo "Node.js not found. Installing..."
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
    sudo apt-get install -y nodejs
  else
    echo "Error: Could not install Node.js"
    exit 1
  fi
else
  NODE_VERSION=$(node -v)
  echo "✓ Node.js $NODE_VERSION installed"
fi;

# 3. Install npm dependencies
echo "Installing npm dependencies..."
cd "$SCRIPT_DIR"
npm ci
echo "✓ npm ci completed"

# 4. Verify installation
echo ""
echo "=== Verification ==="
if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  echo "✓ All dependencies installed"
  echo ""
  echo "Ready for CI!"
  exit 0
else
  echo "✗ Some dependencies missing"
  exit 1
fi;
