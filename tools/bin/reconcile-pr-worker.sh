#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-shell-lib.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-config-lib.sh"

SESSION="${1:?usage: reconcile-pr-worker.sh SESSION}"
WORKSPACE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_YAML="$(resolve_flow_config_yaml "${BASH_SOURCE[0]}")"
AGENT_ROOT="$(flow_resolve_agent_root "${CONFIG_YAML}")"
RUNS_ROOT="$(flow_resolve_runs_root "${CONFIG_YAML}")"
HISTORY_ROOT="$(flow_resolve_history_root "${CONFIG_YAML}")"
REPO_SLUG="$(flow_resolve_repo_slug "${CONFIG_YAML}")"
AGENT_REPO_ROOT="$(flow_resolve_agent_repo_root "${CONFIG_YAML}")"
FLOW_SKILL_DIR="$(resolve_flow_skill_dir "${BASH_SOURCE[0]}")"
FLOW_TOOLS_DIR="${FLOW_SKILL_DIR}/tools/bin"
HOOK_FILE="${FLOW_SKILL_DIR}/hooks/pr-reconcile-hooks.sh"

ACP_AGENT_ROOT="$AGENT_ROOT" \
ACP_RUNS_ROOT="$RUNS_ROOT" \
ACP_HISTORY_ROOT="$HISTORY_ROOT" \
ACP_REPO_SLUG="$REPO_SLUG" \
ACP_AGENT_REPO_ROOT="$AGENT_REPO_ROOT" \
F_LOSNING_RUNS_ROOT="$RUNS_ROOT" \
  bash "${FLOW_TOOLS_DIR}/agent-project-reconcile-pr-session" \
    --session "$SESSION" \
    --repo-slug "$REPO_SLUG" \
    --repo-root "$AGENT_REPO_ROOT" \
    --runs-root "$RUNS_ROOT" \
    --history-root "$HISTORY_ROOT" \
    --hook-file "$HOOK_FILE"
