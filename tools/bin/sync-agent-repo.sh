#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-config-lib.sh"

CONFIG_YAML="$(resolve_flow_config_yaml "${BASH_SOURCE[0]}")"
SOURCE_REPO_ROOT="${ACP_SOURCE_REPO_ROOT:-$(flow_resolve_retained_repo_root "${CONFIG_YAML}")}"
CANONICAL_REPO_ROOT="$(flow_resolve_repo_root "${CONFIG_YAML}")"
AGENT_REPO_ROOT="$(flow_resolve_agent_repo_root "${CONFIG_YAML}")"
DEFAULT_BRANCH="$(flow_resolve_default_branch "${CONFIG_YAML}")"
REMOTE_NAME="${ACP_REMOTE_NAME:-origin}"
FLOW_SKILL_DIR="$(resolve_flow_skill_dir "${BASH_SOURCE[0]}")"
FLOW_TOOLS_DIR="${FLOW_SKILL_DIR}/tools/bin"

is_git_checkout() {
  local repo_root="${1:-}"
  [[ -n "$repo_root" ]] || return 1
  [[ -d "$repo_root/.git" || -f "$repo_root/.git" ]]
}

has_remote() {
  local repo_root="${1:-}"
  [[ -n "$repo_root" ]] || return 1
  git -C "$repo_root" remote get-url "$REMOTE_NAME" >/dev/null 2>&1
}

SYNC_SEED_ROOT="$AGENT_REPO_ROOT"
if ! is_git_checkout "$SYNC_SEED_ROOT" || ! has_remote "$SYNC_SEED_ROOT"; then
  SYNC_SEED_ROOT="$CANONICAL_REPO_ROOT"
fi

if ! is_git_checkout "$SYNC_SEED_ROOT" || ! has_remote "$SYNC_SEED_ROOT"; then
  SYNC_SEED_ROOT="$SOURCE_REPO_ROOT"
fi

if ! is_git_checkout "$SYNC_SEED_ROOT"; then
  echo "[sync-agent-repo] source repo is not a Git checkout: $SYNC_SEED_ROOT" >&2
  exit 1
fi

if ! has_remote "$SYNC_SEED_ROOT"; then
  echo "[sync-agent-repo] missing remote '$REMOTE_NAME' in source repo: $SYNC_SEED_ROOT" >&2
  exit 1
fi

bash "${FLOW_TOOLS_DIR}/agent-project-sync-anchor-repo" \
  --canonical-root "$SYNC_SEED_ROOT" \
  --anchor-root "$AGENT_REPO_ROOT" \
  --remote "$REMOTE_NAME" \
  --default-branch "$DEFAULT_BRANCH"
