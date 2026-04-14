#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-config-lib.sh"

validate_repo_slug_matches_origin() {
  local repo_root="${1:-}"
  local repo_slug="${2:-}"
  local remote_repo_slug=""

  [[ -n "${repo_root}" && -n "${repo_slug}" ]] || return 0
  remote_repo_slug="$(flow_git_remote_repo_slug "${repo_root}" "origin" 2>/dev/null || true)"
  [[ -n "${remote_repo_slug}" ]] || return 0

  if [[ "${remote_repo_slug}" != "${repo_slug}" ]]; then
    printf 'project-init repo slug mismatch: config=%s origin=%s repo_root=%s\n' \
      "${repo_slug}" "${remote_repo_slug}" "${repo_root}" >&2
    return 1
  fi

  return 0
}

usage() {
  cat <<'EOF'
Usage:
  project-init.sh --profile-id <id> --repo-slug <owner/repo> [options]

Initialize a project for agent-control-plane by scaffolding the profile,
running profile smoke checks, adopting runtime roots, and syncing the published
runtime copy.

Common options:
  --profile-id <id>                  Profile id, e.g. billing-api
  --repo-slug <owner/repo>           Forge repo slug
  --profile-home <path>              Installed profile registry root
  --repo-root <path>                 Canonical repo root
  --agent-repo-root <path>           Agent-owned anchor repo root
  --agent-root <path>                Runtime root
  --worktree-root <path>             Worktree parent root
  --retained-repo-root <path>        Retained/manual checkout root
  --vscode-workspace-file <path>     VS Code workspace file
  --coding-worker <codex|openclaw|claude|ollama|pi|opencode|kilo>
  --claude-model <model>
  --claude-permission-mode <mode>
  --claude-effort <level>
  --claude-timeout-seconds <secs>
  --claude-max-attempts <count>
  --claude-retry-backoff-seconds <s>
  --openclaw-model <model>
  --openclaw-thinking <mode>
  --openclaw-timeout-seconds <secs>
  --force                            Overwrite existing profile files

Adopt/sync options:
  --source-repo-root <path>          Optional source repo for anchor sync
  --skip-anchor-sync                 Skip sync-agent-repo during adopt
  --skip-workspace-sync              Skip sync-vscode-workspace during adopt
  --allow-missing-repo               Continue adopt when repos are missing
  --skip-sync                        Do not sync published runtime copy
  --source-home <path>               Shared agent source root for runtime sync
  --runtime-home <path>              Published runtime home for sync
  --help                             Show this help
EOF
}

profile_id=""
repo_slug=""
profile_home=""
repo_root=""
agent_repo_root=""
agent_root=""
worktree_root=""
retained_repo_root=""
vscode_workspace_file=""
coding_worker=""
claude_model=""
claude_permission_mode=""
claude_effort=""
claude_timeout_seconds=""
claude_max_attempts=""
claude_retry_backoff_seconds=""
openclaw_model=""
openclaw_thinking=""
openclaw_timeout_seconds=""
force="0"
source_repo_root=""
skip_anchor_sync="0"
skip_workspace_sync="0"
allow_missing_repo="0"
skip_sync="0"
source_home=""
runtime_home=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile-id) profile_id="${2:-}"; shift 2 ;;
    --repo-slug) repo_slug="${2:-}"; shift 2 ;;
    --profile-home) profile_home="${2:-}"; shift 2 ;;
    --repo-root) repo_root="${2:-}"; shift 2 ;;
    --agent-repo-root) agent_repo_root="${2:-}"; shift 2 ;;
    --agent-root) agent_root="${2:-}"; shift 2 ;;
    --worktree-root) worktree_root="${2:-}"; shift 2 ;;
    --retained-repo-root) retained_repo_root="${2:-}"; shift 2 ;;
    --vscode-workspace-file) vscode_workspace_file="${2:-}"; shift 2 ;;
    --coding-worker) coding_worker="${2:-}"; shift 2 ;;
    --claude-model) claude_model="${2:-}"; shift 2 ;;
    --claude-permission-mode) claude_permission_mode="${2:-}"; shift 2 ;;
    --claude-effort) claude_effort="${2:-}"; shift 2 ;;
    --claude-timeout-seconds) claude_timeout_seconds="${2:-}"; shift 2 ;;
    --claude-max-attempts) claude_max_attempts="${2:-}"; shift 2 ;;
    --claude-retry-backoff-seconds) claude_retry_backoff_seconds="${2:-}"; shift 2 ;;
    --openclaw-model) openclaw_model="${2:-}"; shift 2 ;;
    --openclaw-thinking) openclaw_thinking="${2:-}"; shift 2 ;;
    --openclaw-timeout-seconds) openclaw_timeout_seconds="${2:-}"; shift 2 ;;
    --force) force="1"; shift ;;
    --source-repo-root) source_repo_root="${2:-}"; shift 2 ;;
    --skip-anchor-sync) skip_anchor_sync="1"; shift ;;
    --skip-workspace-sync) skip_workspace_sync="1"; shift ;;
    --allow-missing-repo) allow_missing_repo="1"; shift ;;
    --skip-sync) skip_sync="1"; shift ;;
    --source-home) source_home="${2:-}"; shift 2 ;;
    --runtime-home) runtime_home="${2:-}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 64 ;;
  esac
done

if [[ -z "${profile_id}" || -z "${repo_slug}" ]]; then
  usage >&2
  exit 64
fi

validate_repo_slug_matches_origin "${repo_root:-${agent_repo_root:-}}" "${repo_slug}"

FLOW_SKILL_DIR="$(resolve_flow_skill_dir "${BASH_SOURCE[0]}")"
SCAFFOLD_SCRIPT="${ACP_PROJECT_INIT_SCAFFOLD_SCRIPT:-${FLOW_SKILL_DIR}/tools/bin/scaffold-profile.sh}"
PROFILE_SMOKE_SCRIPT="${ACP_PROJECT_INIT_SMOKE_SCRIPT:-${FLOW_SKILL_DIR}/tools/bin/profile-smoke.sh}"
PROFILE_ADOPT_SCRIPT="${ACP_PROJECT_INIT_ADOPT_SCRIPT:-${FLOW_SKILL_DIR}/tools/bin/profile-adopt.sh}"
SYNC_SCRIPT="${ACP_PROJECT_INIT_SYNC_SCRIPT:-${FLOW_SKILL_DIR}/tools/bin/sync-shared-agent-home.sh}"
SOURCE_HOME="${source_home:-${ACP_PROJECT_INIT_SOURCE_HOME:-$(cd "${FLOW_SKILL_DIR}/../../.." && pwd)}}"
RUNTIME_HOME="${runtime_home:-${ACP_PROJECT_INIT_RUNTIME_HOME:-${HOME}/.agent-runtime/runtime-home}}"

scaffold_cmd=(bash "${SCAFFOLD_SCRIPT}" --profile-id "${profile_id}" --repo-slug "${repo_slug}")
[[ -n "${profile_home}" ]] && scaffold_cmd+=(--profile-home "${profile_home}")
[[ -n "${repo_root}" ]] && scaffold_cmd+=(--repo-root "${repo_root}")
[[ -n "${agent_repo_root}" ]] && scaffold_cmd+=(--agent-repo-root "${agent_repo_root}")
[[ -n "${agent_root}" ]] && scaffold_cmd+=(--agent-root "${agent_root}")
[[ -n "${worktree_root}" ]] && scaffold_cmd+=(--worktree-root "${worktree_root}")
[[ -n "${retained_repo_root}" ]] && scaffold_cmd+=(--retained-repo-root "${retained_repo_root}")
[[ -n "${vscode_workspace_file}" ]] && scaffold_cmd+=(--vscode-workspace-file "${vscode_workspace_file}")
[[ -n "${coding_worker}" ]] && scaffold_cmd+=(--coding-worker "${coding_worker}")
[[ -n "${claude_model}" ]] && scaffold_cmd+=(--claude-model "${claude_model}")
[[ -n "${claude_permission_mode}" ]] && scaffold_cmd+=(--claude-permission-mode "${claude_permission_mode}")
[[ -n "${claude_effort}" ]] && scaffold_cmd+=(--claude-effort "${claude_effort}")
[[ -n "${claude_timeout_seconds}" ]] && scaffold_cmd+=(--claude-timeout-seconds "${claude_timeout_seconds}")
[[ -n "${claude_max_attempts}" ]] && scaffold_cmd+=(--claude-max-attempts "${claude_max_attempts}")
[[ -n "${claude_retry_backoff_seconds}" ]] && scaffold_cmd+=(--claude-retry-backoff-seconds "${claude_retry_backoff_seconds}")
[[ -n "${openclaw_model}" ]] && scaffold_cmd+=(--openclaw-model "${openclaw_model}")
[[ -n "${openclaw_thinking}" ]] && scaffold_cmd+=(--openclaw-thinking "${openclaw_thinking}")
[[ -n "${openclaw_timeout_seconds}" ]] && scaffold_cmd+=(--openclaw-timeout-seconds "${openclaw_timeout_seconds}")
[[ "${force}" == "1" ]] && scaffold_cmd+=(--force)

adopt_cmd=(bash "${PROFILE_ADOPT_SCRIPT}" --profile-id "${profile_id}")
[[ -n "${source_repo_root}" ]] && adopt_cmd+=(--source-repo-root "${source_repo_root}")
[[ "${skip_anchor_sync}" == "1" ]] && adopt_cmd+=(--skip-anchor-sync)
[[ "${skip_workspace_sync}" == "1" ]] && adopt_cmd+=(--skip-workspace-sync)
[[ "${allow_missing_repo}" == "1" ]] && adopt_cmd+=(--allow-missing-repo)

"${scaffold_cmd[@]}" >/dev/null
bash "${PROFILE_SMOKE_SCRIPT}" --profile-id "${profile_id}" >/dev/null
"${adopt_cmd[@]}" >/dev/null

sync_status="skipped"
if [[ "${skip_sync}" != "1" ]]; then
  bash "${SYNC_SCRIPT}" "${SOURCE_HOME}" "${RUNTIME_HOME}" >/dev/null
  sync_status="ok"
fi

printf 'PROJECT_INIT_STATUS=ok\n'
printf 'PROFILE_ID=%s\n' "${profile_id}"
printf 'REPO_SLUG=%s\n' "${repo_slug}"
printf 'PROFILE_SMOKE_STATUS=ok\n'
printf 'PROFILE_ADOPT_STATUS=ok\n'
printf 'RUNTIME_SYNC_STATUS=%s\n' "${sync_status}"
printf 'PROFILE_REGISTRY_ROOT=%s\n' "${profile_home:-$(resolve_flow_profile_registry_root)}"
printf 'RUNTIME_HOME=%s\n' "${RUNTIME_HOME}"
