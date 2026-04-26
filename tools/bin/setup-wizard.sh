#!/usr/bin/env bash
set -euo pipefail

# setup-wizard.sh - Interactive setup wizard for ACP
# Usage: bash tools/bin/setup-wizard.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== ACP Interactive Setup Wizard ===${NC}"
echo ""

# Step 1: Check dependencies
echo -e "${YELLOW}Step 1: Checking dependencies...${NC}"
deps_ok=true
for cmd in node bash git jq python3 tmux; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo -e "  ${RED}✗${NC} $cmd is NOT installed"
    deps_ok=false
  else
    echo -e "  ${GREEN}✓${NC} $cmd is installed"
  fi
done

if [[ "$deps_ok" == "false" ]]; then
  echo ""
  echo -e "${RED}Please install missing dependencies first.${NC}"
  echo "Run: bash tools/bin/setup-verify.sh for detailed instructions"
  exit 1
fi

# Step 2: Choose forge provider
echo ""
echo -e "${YELLOW}Step 2: Choose forge provider${NC}"
echo "  1) GitHub"
echo "  2) Gitea (local)"
read -p "Select option [1-2]: " forge_choice

case "$forge_choice" in
  1)
    FORGE_PROVIDER="github"
    echo -e "${GREEN}Selected: GitHub${NC}"
    
    # Check gh CLI
    if ! command -v gh >/dev/null 2>&1; then
      echo -e "${RED}gh CLI is not installed. Please install it first.${NC}"
      exit 1
    fi
    
    if ! gh auth status &>/dev/null; then
      echo -e "${YELLOW}gh CLI is not authenticated. Running 'gh auth login'...${NC}"
      gh auth login
    fi
    ;;
  2)
    FORGE_PROVIDER="gitea"
    echo -e "${GREEN}Selected: Gitea${NC}"
    read -p "Enter Gitea base URL [http://127.0.0.1:3000]: " GITEA_URL
    GITEA_URL=${GITEA_URL:-http://127.0.0.1:3000}
    read -p "Enter Gitea token: " GITEA_TOKEN
    ;;
  *)
    echo -e "${RED}Invalid option${NC}"
    exit 1
    ;;
esac

# Step 3: Choose coding worker
echo ""
echo -e "${YELLOW}Step 3: Choose coding worker${NC}"
echo "  1) codex (OpenAI Codex)"
echo "  2) claude (Anthropic Claude)"
echo "  3) openclaw"
echo "  4) ollama (local models)"
echo "  5) pi (OpenRouter)"
echo "  6) opencode (Charm Crush)"
echo "  7) kilo (Kilo Code)"
read -p "Select option [1-7]: " worker_choice

case "$worker_choice" in
  1) CODING_WORKER="codex" ;;
  2) CODING_WORKER="claude" ;;
  3) CODING_WORKER="openclaw" ;;
  4) CODING_WORKER="ollama" ;;
  5) CODING_WORKER="pi" ;;
  6) CODING_WORKER="opencode" ;;
  7) CODING_WORKER="kilo" ;;
  *) echo -e "${RED}Invalid option${NC}"; exit 1 ;;
esac

echo -e "${GREEN}Selected: $CODING_WORKER${NC}"

# Check if worker is available
if ! command -v "$CODING_WORKER" >/dev/null 2>&1 && [[ "$CODING_WORKER" != "ollama" ]]; then
  echo -e "${YELLOW}Warning: $CODING_WORKER is not installed.${NC}"
  read -p "Continue anyway? [y/N]: " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Aborted."
    exit 1
  fi
fi

# Step 4: Profile configuration
echo ""
echo -e "${YELLOW}Step 4: Profile configuration${NC}"
read -p "Enter profile ID [my-repo]: " PROFILE_ID
PROFILE_ID=${PROFILE_ID:-my-repo}

read -p "Enter repo slug (owner/repo): " REPO_SLUG
if [[ -z "$REPO_SLUG" ]]; then
  echo -e "${RED}Repo slug is required${NC}"
  exit 1
fi

read -p "Enter repo root path [$(pwd)]: " REPO_ROOT
REPO_ROOT=${REPO_ROOT:-$(pwd)}

# Step 5: Run setup
echo ""
echo -e "${YELLOW}Step 5: Running setup...${NC}"
echo ""

SETUP_ARGS=(
  "--profile-id" "$PROFILE_ID"
  "--repo-slug" "$REPO_SLUG"
  "--forge-provider" "$FORGE_PROVIDER"
  "--repo-root" "$REPO_ROOT"
  "--coding-worker" "$CODING_WORKER"
)

if [[ "$FORGE_PROVIDER" == "gitea" ]]; then
  SETUP_ARGS+=("--gitea-base-url" "$GITEA_URL" "--gitea-token" "$GITEA_TOKEN")
fi

echo "Running: npx agent-control-plane@latest init ${SETUP_ARGS[*]}"
echo ""

if npx agent-control-plane@latest init "${SETUP_ARGS[@]}"; then
  echo ""
  echo -e "${GREEN}✓ Setup completed successfully!${NC}"
  echo ""
  echo "Next steps:"
  echo "  1. Start runtime: npx agent-control-plane@latest runtime start --profile-id $PROFILE_ID"
  echo "  2. Check status: npx agent-control-plane@latest runtime status --profile-id $PROFILE_ID"
  echo "  3. Open dashboard: npx agent-control-plane@latest dashboard start"
else
  echo ""
  echo -e "${RED}✗ Setup failed. Please check the errors above.${NC}"
  exit 1
fi
