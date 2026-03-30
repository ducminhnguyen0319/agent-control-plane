#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-config-lib.sh"

SESSION="${1:?usage: publish-issue-worker.sh SESSION [--dry-run]}"
DRY_RUN="${2:-}"
FLOW_SKILL_DIR="$(resolve_flow_skill_dir "${BASH_SOURCE[0]}")"
FLOW_TOOLS_DIR="${FLOW_SKILL_DIR}/tools/bin"
CONFIG_YAML="$(resolve_flow_config_yaml "${BASH_SOURCE[0]}")"
AGENT_ROOT="$(flow_resolve_agent_root "${CONFIG_YAML}")"
RUNS_ROOT="$(flow_resolve_runs_root "${CONFIG_YAML}")"
HISTORY_ROOT="$(flow_resolve_history_root "${CONFIG_YAML}")"
REPO_SLUG="$(flow_resolve_repo_slug "${CONFIG_YAML}")"
BASE_BRANCH="$(flow_resolve_default_branch "${CONFIG_YAML}")"

ARGS=(
  --repo-slug "$REPO_SLUG"
  --runs-root "$RUNS_ROOT"
  --history-root "$HISTORY_ROOT"
  --session "$SESSION"
  --base-branch "$BASE_BRANCH"
  --remote "origin"
)
if [[ "$DRY_RUN" == "--dry-run" ]]; then
  ARGS+=(--dry-run)
fi

bash "${FLOW_TOOLS_DIR}/agent-project-publish-issue-pr" "${ARGS[@]}"
