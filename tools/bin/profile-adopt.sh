#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-config-lib.sh"

usage() {
  cat <<'EOF'
Usage:
  profile-adopt.sh [--profile-id <id>] [options]

Prepare an available profile for real scheduler use by creating runtime roots,
seeding the agent anchor repo when possible, syncing the VS Code workspace file,
and copying the selected installed profile into the runtime root for quick
operator access.

Options:
  --profile-id <id>                  Profile id to adopt
  --source-repo-root <path>          Optional source repo used when seeding the agent repo
  --skip-anchor-sync                 Do not run sync-agent-repo.sh
  --skip-workspace-sync              Do not run sync-vscode-workspace.sh
  --allow-missing-repo               Continue when canonical/source repos are missing
  --help                             Show this help
EOF
}

profile_id_override=""
source_repo_root_override=""
skip_anchor_sync="0"
skip_workspace_sync="0"
allow_missing_repo="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile-id) profile_id_override="${2:-}"; shift 2 ;;
    --source-repo-root) source_repo_root_override="${2:-}"; shift 2 ;;
    --skip-anchor-sync) skip_anchor_sync="1"; shift ;;
    --skip-workspace-sync) skip_workspace_sync="1"; shift ;;
    --allow-missing-repo) allow_missing_repo="1"; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ -n "$profile_id_override" ]]; then
  export ACP_PROJECT_ID="$profile_id_override"
  export AGENT_PROJECT_ID="$profile_id_override"
fi

FLOW_SKILL_DIR="$(resolve_flow_skill_dir "${BASH_SOURCE[0]}")"
CONFIG_YAML="$(resolve_flow_config_yaml "${BASH_SOURCE[0]}")"
PROFILE_ID="$(flow_resolve_adapter_id "${CONFIG_YAML}")"
PROFILE_REGISTRY_ROOT="$(resolve_flow_profile_registry_root)"
if [[ ! -f "${CONFIG_YAML}" ]]; then
  echo "[profile-adopt] missing installed profile config: ${CONFIG_YAML}" >&2
  exit 1
fi

REPO_SLUG="$(flow_resolve_repo_slug "${CONFIG_YAML}")"
DEFAULT_BRANCH="$(flow_resolve_default_branch "${CONFIG_YAML}")"
PROJECT_LABEL="$(flow_resolve_project_label "${CONFIG_YAML}")"
REPO_ROOT="$(flow_resolve_repo_root "${CONFIG_YAML}")"
AGENT_REPO_ROOT="$(flow_resolve_agent_repo_root "${CONFIG_YAML}")"
AGENT_ROOT="$(flow_resolve_agent_root "${CONFIG_YAML}")"
RUNS_ROOT="$(flow_resolve_runs_root "${CONFIG_YAML}")"
STATE_ROOT="$(flow_resolve_state_root "${CONFIG_YAML}")"
HISTORY_ROOT="$(flow_resolve_history_root "${CONFIG_YAML}")"
WORKTREE_ROOT="$(flow_resolve_worktree_root "${CONFIG_YAML}")"
RETAINED_REPO_ROOT="$(flow_resolve_retained_repo_root "${CONFIG_YAML}")"
VSCODE_WORKSPACE_FILE="$(flow_resolve_vscode_workspace_file "${CONFIG_YAML}")"
REMOTE_NAME="${ACP_REMOTE_NAME:-origin}"
SOURCE_REPO_ROOT="${source_repo_root_override:-${ACP_SOURCE_REPO_ROOT:-${RETAINED_REPO_ROOT}}}"
PROFILE_LINK="${AGENT_ROOT}/control-plane.yaml"
WORKSPACE_LINK="${AGENT_ROOT}/workspace.code-workspace"
INSTALLED_PROFILE_DIR="$(dirname "${CONFIG_YAML}")"
FLOW_TOOLS_DIR="${FLOW_SKILL_DIR}/tools/bin"
PROFILE_SMOKE_SCRIPT="${FLOW_TOOLS_DIR}/profile-smoke.sh"
SYNC_AGENT_REPO_SCRIPT="${FLOW_TOOLS_DIR}/sync-agent-repo.sh"
SYNC_VSCODE_WORKSPACE_SCRIPT="${FLOW_TOOLS_DIR}/sync-vscode-workspace.sh"

canonical_copy_source() {
  local target_path="${1:-}"
  local target_dir=""
  local target_name=""

  [[ -n "$target_path" ]] || return 1
  target_dir="$(dirname "$target_path")"
  target_name="$(basename "$target_path")"
  target_dir="$(cd "$target_dir" && pwd -P)"
  printf '%s/%s\n' "$target_dir" "$target_name"
}

path_status() {
  local path="${1:-}"
  if [[ -z "$path" ]]; then
    printf 'missing\n'
  elif [[ -d "$path/.git" || -f "$path/.git" ]]; then
    printf 'git\n'
  elif [[ -e "$path" ]]; then
    printf 'exists\n'
  else
    printf 'missing\n'
  fi
}

repo_has_remote() {
  local repo_root="${1:-}"
  local remote_name="${2:-origin}"
  [[ -n "$repo_root" ]] || return 1
  [[ -d "$repo_root/.git" || -f "$repo_root/.git" ]] || return 1
  git -C "$repo_root" remote get-url "$remote_name" >/dev/null 2>&1
}

if ! smoke_output="$(ACP_PROJECT_ID="$PROFILE_ID" bash "$PROFILE_SMOKE_SCRIPT" --profile-id "$PROFILE_ID" 2>&1)"; then
  printf '%s\n' "$smoke_output" >&2
  exit 1
fi

mkdir -p "$AGENT_ROOT" "$RUNS_ROOT" "$STATE_ROOT" "$HISTORY_ROOT" "$WORKTREE_ROOT" "$(dirname "$VSCODE_WORKSPACE_FILE")"
copy_file_into_runtime() {
  local source_file="${1:?source file required}"
  local target_file="${2:?target file required}"
  mkdir -p "$(dirname "$target_file")"
  if [[ -L "$target_file" || -f "$target_file" ]]; then
    rm -f "$target_file"
  elif [[ -d "$target_file" ]]; then
    rm -rf "$target_file"
  fi
  cp "$source_file" "$target_file"
}

copy_file_into_runtime "$(canonical_copy_source "$CONFIG_YAML")" "$PROFILE_LINK"

warnings=0
anchor_sync_status="skipped"
workspace_sync_status="skipped"

canonical_repo_status="$(path_status "$REPO_ROOT")"
source_repo_status="$(path_status "$SOURCE_REPO_ROOT")"
agent_repo_status_before="$(path_status "$AGENT_REPO_ROOT")"

if [[ "$skip_anchor_sync" == "1" ]]; then
  anchor_sync_status="skipped"
else
  if repo_has_remote "$REPO_ROOT" "$REMOTE_NAME" || repo_has_remote "$SOURCE_REPO_ROOT" "$REMOTE_NAME"; then
    ACP_PROJECT_ID="$PROFILE_ID" \
    ACP_REPO_ROOT="$REPO_ROOT" \
    ACP_AGENT_REPO_ROOT="$AGENT_REPO_ROOT" \
    ACP_RETAINED_REPO_ROOT="$RETAINED_REPO_ROOT" \
    ACP_SOURCE_REPO_ROOT="$SOURCE_REPO_ROOT" \
    ACP_DEFAULT_BRANCH="$DEFAULT_BRANCH" \
    ACP_REMOTE_NAME="$REMOTE_NAME" \
      bash "$SYNC_AGENT_REPO_SCRIPT" >/dev/null
    anchor_sync_status="ok"
  elif [[ "$allow_missing_repo" == "1" ]]; then
    anchor_sync_status="skipped-missing-repo"
    warnings=$((warnings + 1))
  else
    echo "[profile-adopt] no Git source with remote '${REMOTE_NAME}' for profile ${PROFILE_ID}" >&2
    exit 1
  fi
fi

if [[ "$skip_workspace_sync" == "1" ]]; then
  workspace_sync_status="skipped"
else
  ACP_PROJECT_ID="$PROFILE_ID" \
  ACP_REPO_ROOT="$REPO_ROOT" \
  ACP_AGENT_REPO_ROOT="$AGENT_REPO_ROOT" \
  ACP_RETAINED_REPO_ROOT="$RETAINED_REPO_ROOT" \
  ACP_VSCODE_WORKSPACE_FILE="$VSCODE_WORKSPACE_FILE" \
  ACP_DEFAULT_BRANCH="$DEFAULT_BRANCH" \
    bash "$SYNC_VSCODE_WORKSPACE_SCRIPT" >/dev/null
  workspace_sync_status="ok"
fi

if [[ -f "$VSCODE_WORKSPACE_FILE" ]]; then
  copy_file_into_runtime "$(canonical_copy_source "$VSCODE_WORKSPACE_FILE")" "$WORKSPACE_LINK"
else
  rm -f "$WORKSPACE_LINK"
fi

# Keep the configured anchor root materialized even when anchor sync is skipped
# so later setup/runtime steps can rely on the path existing.
if [[ "$anchor_sync_status" != "ok" && ! -e "$AGENT_REPO_ROOT" ]]; then
  mkdir -p "$AGENT_REPO_ROOT"
fi

agent_repo_status_after="$(path_status "$AGENT_REPO_ROOT")"
workspace_file_status="$(path_status "$VSCODE_WORKSPACE_FILE")"
adopt_status="ok"
if (( warnings > 0 )); then
  adopt_status="ok-with-warnings"
fi

printf 'PROFILE_ID=%s\n' "$PROFILE_ID"
printf 'PROJECT_LABEL=%s\n' "$PROJECT_LABEL"
printf 'PROFILE_REGISTRY_ROOT=%s\n' "$PROFILE_REGISTRY_ROOT"
printf 'INSTALLED_PROFILE_DIR=%s\n' "$INSTALLED_PROFILE_DIR"
printf 'CONFIG_YAML=%s\n' "$CONFIG_YAML"
printf 'REPO_SLUG=%s\n' "$REPO_SLUG"
printf 'DEFAULT_BRANCH=%s\n' "$DEFAULT_BRANCH"
printf 'REMOTE_NAME=%s\n' "$REMOTE_NAME"
printf 'REPO_ROOT=%s\n' "$REPO_ROOT"
printf 'SOURCE_REPO_ROOT=%s\n' "$SOURCE_REPO_ROOT"
printf 'AGENT_REPO_ROOT=%s\n' "$AGENT_REPO_ROOT"
printf 'AGENT_ROOT=%s\n' "$AGENT_ROOT"
printf 'RUNS_ROOT=%s\n' "$RUNS_ROOT"
printf 'STATE_ROOT=%s\n' "$STATE_ROOT"
printf 'HISTORY_ROOT=%s\n' "$HISTORY_ROOT"
printf 'WORKTREE_ROOT=%s\n' "$WORKTREE_ROOT"
printf 'VSCODE_WORKSPACE_FILE=%s\n' "$VSCODE_WORKSPACE_FILE"
printf 'PROFILE_LINK=%s\n' "$PROFILE_LINK"
printf 'WORKSPACE_LINK=%s\n' "$WORKSPACE_LINK"
printf 'CANONICAL_REPO_STATUS=%s\n' "$canonical_repo_status"
printf 'SOURCE_REPO_STATUS=%s\n' "$source_repo_status"
printf 'AGENT_REPO_STATUS_BEFORE=%s\n' "$agent_repo_status_before"
printf 'AGENT_REPO_STATUS_AFTER=%s\n' "$agent_repo_status_after"
printf 'WORKSPACE_FILE_STATUS=%s\n' "$workspace_file_status"
printf 'PROFILE_SMOKE_STATUS=ok\n'
printf 'ANCHOR_SYNC_STATUS=%s\n' "$anchor_sync_status"
printf 'WORKSPACE_SYNC_STATUS=%s\n' "$workspace_sync_status"
printf 'WARNING_COUNT=%s\n' "$warnings"
printf 'ADOPT_STATUS=%s\n' "$adopt_status"
