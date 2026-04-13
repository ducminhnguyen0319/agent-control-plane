#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-config-lib.sh"

FLOW_SKILL_DIR="$(resolve_flow_skill_dir "${BASH_SOURCE[0]}")"
FLOW_TOOLS_DIR="${FLOW_SKILL_DIR}/tools/bin"
CONFIG_YAML="$(resolve_flow_config_yaml "${BASH_SOURCE[0]}")"
AGENT_REPO_ROOT="$(flow_resolve_agent_repo_root "${CONFIG_YAML}")"
AGENT_ROOT="$(flow_resolve_agent_root "${CONFIG_YAML}")"
RUNS_ROOT="$(flow_resolve_runs_root "${CONFIG_YAML}")"
HISTORY_ROOT="$(flow_resolve_history_root "${CONFIG_YAML}")"
WORKTREE_ROOT="$(flow_resolve_worktree_root "${CONFIG_YAML}")"
RETAINED_REPO_ROOT="$(flow_resolve_retained_repo_root "${CONFIG_YAML}")"
VSCODE_WORKSPACE_FILE="$(flow_resolve_vscode_workspace_file "${CONFIG_YAML}")"
ISSUE_SESSION_PREFIX="$(flow_resolve_issue_session_prefix "${CONFIG_YAML}")"
PR_SESSION_PREFIX="$(flow_resolve_pr_session_prefix "${CONFIG_YAML}")"
WORKTREE="${1-}"
SESSION="${2:-}"
MODE="generic"
ARGS=(
  --repo-root "$AGENT_REPO_ROOT"
  --runs-root "$RUNS_ROOT"
  --history-root "$HISTORY_ROOT"
  --worktree "${WORKTREE:-}"
)

case "$SESSION" in
  "${ISSUE_SESSION_PREFIX}"*) MODE="issue" ;;
  "${PR_SESSION_PREFIX}"*) MODE="pr" ;;
esac

ARGS+=(--mode "$MODE")
if [[ -n "$SESSION" ]]; then
  ARGS+=(--session "$SESSION")
fi

cleanup_exit=0
AGENT_PROJECT_WORKTREE_ROOT="$WORKTREE_ROOT" \
F_LOSNING_WORKTREE_ROOT="$WORKTREE_ROOT" \
  bash "${FLOW_TOOLS_DIR}/agent-project-cleanup-session" "${ARGS[@]}" >/dev/null || cleanup_exit=$?

F_LOSNING_AGENT_REPO_ROOT="$AGENT_REPO_ROOT" \
F_LOSNING_RETAINED_REPO_ROOT="$RETAINED_REPO_ROOT" \
F_LOSNING_VSCODE_WORKSPACE_FILE="$VSCODE_WORKSPACE_FILE" \
  "${FLOW_TOOLS_DIR}/sync-vscode-workspace.sh" >/dev/null 2>&1 || true

if [[ "$cleanup_exit" -ne 0 ]]; then
  exit "$cleanup_exit"
fi
