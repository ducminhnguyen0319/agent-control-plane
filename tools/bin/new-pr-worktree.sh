#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-config-lib.sh"

FLOW_SKILL_DIR="$(resolve_flow_skill_dir "${BASH_SOURCE[0]}")"
if ! flow_require_explicit_profile_selection "${FLOW_SKILL_DIR}" "new-pr-worktree.sh"; then
  exit 64
fi
FLOW_TOOLS_DIR="${FLOW_SKILL_DIR}/tools/bin"
flow_export_project_env_aliases
CONFIG_YAML="$(resolve_flow_config_yaml "${BASH_SOURCE[0]}")"
AGENT_REPO_ROOT="$(flow_resolve_agent_repo_root "${CONFIG_YAML}")"
AUTOMATION_REPO_ROOT="$(flow_resolve_repo_root "${CONFIG_YAML}")"
WORKTREE_ROOT="$(flow_resolve_worktree_root "${CONFIG_YAML}")"
RETAINED_REPO_ROOT="$(flow_resolve_retained_repo_root "${CONFIG_YAML}")"
VSCODE_WORKSPACE_FILE="$(flow_resolve_vscode_workspace_file "${CONFIG_YAML}")"
PR_WORKTREE_BRANCH_PREFIX="$(flow_resolve_pr_worktree_branch_prefix "${CONFIG_YAML}")"

PR_NUMBER="${1:?usage: new-pr-worktree.sh PR_NUMBER HEAD_REF}"
HEAD_REF="${2:?usage: new-pr-worktree.sh PR_NUMBER HEAD_REF}"

ACP_AGENT_REPO_ROOT="$AGENT_REPO_ROOT" \
F_LOSNING_AGENT_REPO_ROOT="$AGENT_REPO_ROOT" \
  "${SCRIPT_DIR}/sync-agent-repo.sh" >/dev/null

export ACP_REPO_ROOT="$AUTOMATION_REPO_ROOT"
export F_LOSNING_REPO_ROOT="$AUTOMATION_REPO_ROOT"

WORKTREE_OUT="$(
  bash "${FLOW_TOOLS_DIR}/agent-project-open-pr-worktree" \
    --repo-root "$AGENT_REPO_ROOT" \
    --worktree-root "$WORKTREE_ROOT" \
    --pr-number "$PR_NUMBER" \
    --head-ref "$HEAD_REF" \
    --local-branch-prefix "$PR_WORKTREE_BRANCH_PREFIX" \
    --prepare-script "${SCRIPT_DIR}/prepare-worktree.sh"
)"

ACP_AGENT_REPO_ROOT="$AGENT_REPO_ROOT" \
ACP_RETAINED_REPO_ROOT="$RETAINED_REPO_ROOT" \
ACP_VSCODE_WORKSPACE_FILE="$VSCODE_WORKSPACE_FILE" \
F_LOSNING_AGENT_REPO_ROOT="$AGENT_REPO_ROOT" \
F_LOSNING_RETAINED_REPO_ROOT="$RETAINED_REPO_ROOT" \
F_LOSNING_VSCODE_WORKSPACE_FILE="$VSCODE_WORKSPACE_FILE" \
  "${SCRIPT_DIR}/sync-vscode-workspace.sh" >/dev/null 2>&1 || true

printf '%s\n' "$WORKTREE_OUT"
