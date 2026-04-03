#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-config-lib.sh"

MODE="${1:?usage: run-codex-task.sh MODE SESSION WORKTREE PROMPT_FILE}"
SESSION="${2:?usage: run-codex-task.sh MODE SESSION WORKTREE PROMPT_FILE}"
WORKTREE="${3:?usage: run-codex-task.sh MODE SESSION WORKTREE PROMPT_FILE}"
PROMPT_FILE="${4:?usage: run-codex-task.sh MODE SESSION WORKTREE PROMPT_FILE}"

WORKSPACE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_YAML="$(resolve_flow_config_yaml "${BASH_SOURCE[0]}")"
flow_export_execution_env "${CONFIG_YAML}"
flow_export_project_env_aliases
AGENT_ROOT="$(flow_resolve_agent_root "${CONFIG_YAML}")"
RUNS_ROOT="$(flow_resolve_runs_root "${CONFIG_YAML}")"
AGENT_REPO_ROOT="$(flow_resolve_agent_repo_root "${CONFIG_YAML}")"
CANONICAL_REPO_ROOT="$(flow_resolve_repo_root "${CONFIG_YAML}")"
WORKTREE_ROOT="$(flow_resolve_worktree_root "${CONFIG_YAML}")"
DEPENDENCY_SOURCE_ROOT="${ACP_DEPENDENCY_SOURCE_ROOT:-${F_LOSNING_DEPENDENCY_SOURCE_ROOT:-$CANONICAL_REPO_ROOT}}"
RETAINED_REPO_ROOT="$(flow_resolve_retained_repo_root "${CONFIG_YAML}")"
ISSUE_ID="${ACP_ISSUE_ID:-${F_LOSNING_ISSUE_ID:-}}"
ISSUE_URL="${ACP_ISSUE_URL:-${F_LOSNING_ISSUE_URL:-}}"
ISSUE_AUTOMERGE="${ACP_ISSUE_AUTOMERGE:-${F_LOSNING_ISSUE_AUTOMERGE:-no}}"
PR_NUMBER="${ACP_PR_NUMBER:-${F_LOSNING_PR_NUMBER:-}}"
PR_URL="${ACP_PR_URL:-${F_LOSNING_PR_URL:-}}"
PR_HEAD_REF="${ACP_PR_HEAD_REF:-${F_LOSNING_PR_HEAD_REF:-}}"
FLOW_SKILL_DIR="$(resolve_flow_skill_dir "${BASH_SOURCE[0]}")"
FLOW_TOOLS_DIR="${FLOW_SKILL_DIR}/tools/bin"
TASK_KIND="task"
TASK_ID="$SESSION"
RECONCILE_COMMAND=""
ADAPTER_ID="$(flow_resolve_adapter_id "${CONFIG_YAML}")"
ISSUE_SESSION_PREFIX="$(flow_resolve_issue_session_prefix "${CONFIG_YAML}")"
PR_SESSION_PREFIX="$(flow_resolve_pr_session_prefix "${CONFIG_YAML}")"
CODING_WORKER="${ACP_CODING_WORKER:-codex}"
CODEX_PROFILE_SAFE="${ACP_CODEX_PROFILE_SAFE:-${F_LOSNING_CODEX_PROFILE_SAFE:-${CODEX_PROFILE_SAFE:-f_losning_safe_auto}}}"
CODEX_PROFILE_BYPASS="${ACP_CODEX_PROFILE_BYPASS:-${F_LOSNING_CODEX_PROFILE_BYPASS:-${CODEX_PROFILE_BYPASS:-f_losning_yolo}}}"
if [[ "$MODE" == "bypass" ]]; then
  CLAUDE_PERMISSION_MODE_DEFAULT="bypassPermissions"
else
  CLAUDE_PERMISSION_MODE_DEFAULT="acceptEdits"
fi
CLAUDE_MODEL="${ACP_CLAUDE_MODEL:-${F_LOSNING_CLAUDE_MODEL:-sonnet}}"
CLAUDE_PERMISSION_MODE="${ACP_CLAUDE_PERMISSION_MODE:-${F_LOSNING_CLAUDE_PERMISSION_MODE:-${CLAUDE_PERMISSION_MODE_DEFAULT}}}"
CLAUDE_EFFORT="${ACP_CLAUDE_EFFORT:-${F_LOSNING_CLAUDE_EFFORT:-medium}}"
CLAUDE_TIMEOUT_SECONDS="${ACP_CLAUDE_TIMEOUT_SECONDS:-${F_LOSNING_CLAUDE_TIMEOUT_SECONDS:-900}}"
CLAUDE_MAX_ATTEMPTS="${ACP_CLAUDE_MAX_ATTEMPTS:-${F_LOSNING_CLAUDE_MAX_ATTEMPTS:-3}}"
CLAUDE_RETRY_BACKOFF_SECONDS="${ACP_CLAUDE_RETRY_BACKOFF_SECONDS:-${F_LOSNING_CLAUDE_RETRY_BACKOFF_SECONDS:-30}}"
RESIDENT_WORKER_ENABLED="${ACP_RESIDENT_WORKER_ENABLED:-${F_LOSNING_RESIDENT_WORKER_ENABLED:-}}"
RESIDENT_WORKER_KEY="${ACP_RESIDENT_WORKER_KEY:-${F_LOSNING_RESIDENT_WORKER_KEY:-}}"
RESIDENT_WORKER_DIR="${ACP_RESIDENT_WORKER_DIR:-${F_LOSNING_RESIDENT_WORKER_DIR:-}}"
RESIDENT_WORKER_META_FILE="${ACP_RESIDENT_WORKER_META_FILE:-${F_LOSNING_RESIDENT_WORKER_META_FILE:-}}"
RESIDENT_TASK_COUNT="${ACP_RESIDENT_TASK_COUNT:-${F_LOSNING_RESIDENT_TASK_COUNT:-}}"
RESIDENT_WORKTREE_REUSED="${ACP_RESIDENT_WORKTREE_REUSED:-${F_LOSNING_RESIDENT_WORKTREE_REUSED:-}}"
RESIDENT_OPENCLAW_AGENT_ID="${ACP_RESIDENT_OPENCLAW_AGENT_ID:-${F_LOSNING_RESIDENT_OPENCLAW_AGENT_ID:-}}"
RESIDENT_OPENCLAW_SESSION_ID="${ACP_RESIDENT_OPENCLAW_SESSION_ID:-${F_LOSNING_RESIDENT_OPENCLAW_SESSION_ID:-}}"
RESIDENT_OPENCLAW_AGENT_DIR="${ACP_RESIDENT_OPENCLAW_AGENT_DIR:-${F_LOSNING_RESIDENT_OPENCLAW_AGENT_DIR:-}}"
RESIDENT_OPENCLAW_STATE_DIR="${ACP_RESIDENT_OPENCLAW_STATE_DIR:-${F_LOSNING_RESIDENT_OPENCLAW_STATE_DIR:-}}"
RESIDENT_OPENCLAW_CONFIG_PATH="${ACP_RESIDENT_OPENCLAW_CONFIG_PATH:-${F_LOSNING_RESIDENT_OPENCLAW_CONFIG_PATH:-}}"
# Set defaults if not set from yaml or env
OPENCLAW_MODEL="${OPENCLAW_MODEL:-${ACP_OPENCLAW_MODEL:-${F_LOSNING_OPENCLAW_MODEL:-openrouter/qwen/qwen3.6-plus-preview:free}}}"
OPENCLAW_THINKING="${OPENCLAW_THINKING:-${ACP_OPENCLAW_THINKING:-${F_LOSNING_OPENCLAW_THINKING:-low}}}"
OPENCLAW_TIMEOUT_SECONDS="${OPENCLAW_TIMEOUT_SECONDS:-${ACP_OPENCLAW_TIMEOUT_SECONDS:-${F_LOSNING_OPENCLAW_TIMEOUT_SECONDS:-900}}}"
printf -v SESSION_Q '%q' "$SESSION"
printf -v CONFIG_YAML_Q '%q' "$CONFIG_YAML"
printf -v ADAPTER_ID_Q '%q' "$ADAPTER_ID"
RECONCILE_ENV_PREFIX="ACP_PROJECT_ID=${ADAPTER_ID_Q} AGENT_PROJECT_ID=${ADAPTER_ID_Q} AGENT_CONTROL_PLANE_CONFIG=${CONFIG_YAML_Q} ACP_CONFIG=${CONFIG_YAML_Q}"

case "$SESSION" in
  "${ISSUE_SESSION_PREFIX}"*)
    TASK_KIND="issue"
    TASK_ID="${ISSUE_ID:-${SESSION#${ISSUE_SESSION_PREFIX}}}"
    if [[ "${RESIDENT_WORKER_ENABLED}" != "yes" ]]; then
      RECONCILE_COMMAND="${RECONCILE_ENV_PREFIX} ${WORKSPACE_DIR}/bin/reconcile-issue-worker.sh ${SESSION_Q}"
    fi
    ;;
  "${PR_SESSION_PREFIX}"*)
    TASK_KIND="pr"
    TASK_ID="${PR_NUMBER:-${SESSION#${PR_SESSION_PREFIX}}}"
    RECONCILE_COMMAND="${RECONCILE_ENV_PREFIX} ${WORKSPACE_DIR}/bin/reconcile-pr-worker.sh ${SESSION_Q}"
    ;;
esac

realpath_safe() {
  local path="${1:-}"
  [[ -n "$path" ]] || return 1
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$path" <<'PY'
import os
import sys
print(os.path.realpath(sys.argv[1]))
PY
    return
  fi
  cd "$path" 2>/dev/null && pwd -P
}

assert_isolated_worker_worktree() {
  local worktree_real worktree_root_real canonical_real retained_real git_common_dir expected_git_common_dir
  worktree_real="$(realpath_safe "$WORKTREE")"
  worktree_root_real="$(realpath_safe "$WORKTREE_ROOT")"
  canonical_real="$(realpath_safe "$CANONICAL_REPO_ROOT")"
  retained_real="$(realpath_safe "$RETAINED_REPO_ROOT")"
  expected_git_common_dir="$(realpath_safe "${AGENT_REPO_ROOT}/.git")"

  if [[ -z "$worktree_real" || ! -d "$worktree_real" ]]; then
    echo "invalid worker worktree: $WORKTREE" >&2
    exit 1
  fi

  if [[ -n "$canonical_real" && "$worktree_real" == "$canonical_real" ]]; then
    echo "refusing to run worker in canonical checkout: $worktree_real" >&2
    exit 1
  fi

  if [[ -n "$retained_real" && ( "$worktree_real" == "$retained_real" || "${worktree_real}/" == "${retained_real}/"* ) ]]; then
    echo "refusing to run worker in retained checkout: $worktree_real" >&2
    exit 1
  fi

  if [[ -z "$worktree_root_real" || "${worktree_real}/" != "${worktree_root_real}/"* ]]; then
    echo "refusing to run worker outside managed worktree root: $worktree_real" >&2
    exit 1
  fi

  git_common_dir="$(git -C "$WORKTREE" rev-parse --git-common-dir 2>/dev/null || true)"
  if [[ -z "$git_common_dir" ]]; then
    echo "unable to resolve git common dir for worker worktree: $worktree_real" >&2
    exit 1
  fi
  if [[ "$git_common_dir" == /* ]]; then
    git_common_dir="$(realpath_safe "$git_common_dir")"
  else
    git_common_dir="$(realpath_safe "$WORKTREE/$git_common_dir")"
  fi
  if [[ -z "$expected_git_common_dir" || "$git_common_dir" != "$expected_git_common_dir" ]]; then
    echo "refusing to run worker with non-agent git dir: $git_common_dir" >&2
    exit 1
  fi
}

assert_isolated_worker_worktree

ARGS=(
  --mode "$MODE"
  --session "$SESSION"
  --worktree "$WORKTREE"
  --prompt-file "$PROMPT_FILE"
  --runs-root "$RUNS_ROOT"
  --adapter-id "$ADAPTER_ID"
  --task-kind "$TASK_KIND"
  --task-id "$TASK_ID"
  --env-prefix "F_LOSNING_"
  --context "ISSUE_ID=${ISSUE_ID}"
  --context "ISSUE_URL=${ISSUE_URL}"
  --context "ISSUE_AUTOMERGE=${ISSUE_AUTOMERGE}"
  --context "PR_NUMBER=${PR_NUMBER}"
  --context "PR_URL=${PR_URL}"
  --context "PR_HEAD_REF=${PR_HEAD_REF}"
  --context "CODING_WORKER=${CODING_WORKER}"
  --context "FLOW_TOOLS_DIR=${FLOW_TOOLS_DIR}"
  --context "RESIDENT_WORKER_ENABLED=${RESIDENT_WORKER_ENABLED}"
  --context "RESIDENT_WORKER_KEY=${RESIDENT_WORKER_KEY}"
  --context "RESIDENT_WORKER_DIR=${RESIDENT_WORKER_DIR}"
  --context "RESIDENT_WORKER_META_FILE=${RESIDENT_WORKER_META_FILE}"
  --context "RESIDENT_TASK_COUNT=${RESIDENT_TASK_COUNT}"
  --context "RESIDENT_WORKTREE_REUSED=${RESIDENT_WORKTREE_REUSED}"
  --context "RESIDENT_OPENCLAW_AGENT_ID=${RESIDENT_OPENCLAW_AGENT_ID}"
  --context "RESIDENT_OPENCLAW_SESSION_ID=${RESIDENT_OPENCLAW_SESSION_ID}"
  --context "RESIDENT_OPENCLAW_AGENT_DIR=${RESIDENT_OPENCLAW_AGENT_DIR}"
  --context "RESIDENT_OPENCLAW_STATE_DIR=${RESIDENT_OPENCLAW_STATE_DIR}"
  --context "RESIDENT_OPENCLAW_CONFIG_PATH=${RESIDENT_OPENCLAW_CONFIG_PATH}"
  --collect-file "pr-comment.md"
  --collect-file "issue-comment.md"
  --collect-file "verification.jsonl"
)
if [[ -n "$RECONCILE_COMMAND" ]]; then
  ARGS+=(--reconcile-command "$RECONCILE_COMMAND")
fi

case "$CODING_WORKER" in
  codex)
    ARGS+=(
      --safe-profile "${CODEX_PROFILE_SAFE}"
      --bypass-profile "${CODEX_PROFILE_BYPASS}"
    )
    bash "${FLOW_TOOLS_DIR}/agent-project-run-codex-session" "${ARGS[@]}"
    ;;
  claude)
    ARGS+=(
      --claude-model "${CLAUDE_MODEL}"
      --claude-permission-mode "${CLAUDE_PERMISSION_MODE}"
      --claude-effort "${CLAUDE_EFFORT}"
      --claude-timeout-seconds "${CLAUDE_TIMEOUT_SECONDS}"
      --claude-max-attempts "${CLAUDE_MAX_ATTEMPTS}"
      --claude-retry-backoff-seconds "${CLAUDE_RETRY_BACKOFF_SECONDS}"
    )
    bash "${FLOW_TOOLS_DIR}/agent-project-run-claude-session" "${ARGS[@]}"
    ;;
  openclaw)
    ARGS+=(
      --openclaw-model "${OPENCLAW_MODEL}"
      --openclaw-thinking "${OPENCLAW_THINKING}"
      --openclaw-timeout-seconds "${OPENCLAW_TIMEOUT_SECONDS}"
    )
    if [[ "${RESIDENT_WORKER_ENABLED}" == "yes" ]]; then
      ARGS+=(
        --keep-agent
        --openclaw-agent-id "${RESIDENT_OPENCLAW_AGENT_ID}"
        --openclaw-session-id "${RESIDENT_OPENCLAW_SESSION_ID}"
        --openclaw-agent-dir "${RESIDENT_OPENCLAW_AGENT_DIR}"
        --openclaw-state-dir "${RESIDENT_OPENCLAW_STATE_DIR}"
        --openclaw-config-path "${RESIDENT_OPENCLAW_CONFIG_PATH}"
      )
    fi
    bash "${FLOW_TOOLS_DIR}/agent-project-run-openclaw-session" "${ARGS[@]}"
    ;;
  opencode)
    bash "${FLOW_TOOLS_DIR}/agent-project-run-opencode-session" "${ARGS[@]}"
    ;;
  kilo)
    bash "${FLOW_TOOLS_DIR}/agent-project-run-kilo-session" "${ARGS[@]}"
    ;;
  *)
    echo "unsupported coding worker: ${CODING_WORKER}" >&2
    exit 1
    ;;
esac
