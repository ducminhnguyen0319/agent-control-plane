#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-config-lib.sh"

CONFIG_YAML="$(resolve_flow_config_yaml "${BASH_SOURCE[0]}")"
RETAINED_ROOT="$(flow_resolve_retained_repo_root "${CONFIG_YAML}")"
WORKTREE_ROOT="$(flow_resolve_worktree_root "${CONFIG_YAML}")"
AGENT_ROOT="$(flow_resolve_agent_root "${CONFIG_YAML}")"
RUNS_ROOT="$(flow_resolve_runs_root "${CONFIG_YAML}")"
ADAPTER_ID="$(flow_resolve_adapter_id "${CONFIG_YAML}")"
ADAPTER_ID_REGEX="$(flow_escape_regex "${ADAPTER_ID}")"
ISSUE_SESSION_PREFIX="$(flow_resolve_issue_session_prefix "${CONFIG_YAML}")"
PR_SESSION_PREFIX="$(flow_resolve_pr_session_prefix "${CONFIG_YAML}")"
ISSUE_BRANCH_PREFIX="$(flow_resolve_issue_branch_prefix "${CONFIG_YAML}")"
PR_WORKTREE_BRANCH_PREFIX="$(flow_resolve_pr_worktree_branch_prefix "${CONFIG_YAML}")"
MANAGED_PR_BRANCH_GLOBS="$(flow_resolve_managed_pr_branch_globs "${CONFIG_YAML}")"
ISSUE_BRANCH_PREFIX_REGEX="$(flow_escape_regex "${ISSUE_BRANCH_PREFIX}")"
PR_WORKTREE_BRANCH_PREFIX_REGEX="$(flow_escape_regex "${PR_WORKTREE_BRANCH_PREFIX}")"

cleanup="false"
strict="false"

usage() {
  cat <<'EOF'
Usage:
  audit-retained-worktrees.sh [--cleanup] [--strict]

Audits the retained human checkout for legacy automation worktrees that still
attach to the retained repo's .git/worktrees metadata.

Options:
  --cleanup  Remove clean orphaned automation worktrees automatically.
  --strict   Exit non-zero when any legacy automation worktree is found.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cleanup) cleanup="true"; shift ;;
    --strict) strict="true"; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ ! -d "$RETAINED_ROOT/.git" && ! -f "$RETAINED_ROOT/.git" ]]; then
  echo "retained root is not a Git checkout: $RETAINED_ROOT" >&2
  exit 1
fi

session_for_worktree() {
  local worktree_path="${1:-}"
  local branch_ref="${2:-}"
  local base

  base="$(basename "$worktree_path")"
  if [[ "$base" =~ ^${ADAPTER_ID_REGEX}-pr-([0-9]+)$ ]]; then
    printf '%s%s\n' "${PR_SESSION_PREFIX}" "${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ "$base" =~ ^pr-([0-9]+)- ]]; then
    printf '%s%s\n' "${PR_SESSION_PREFIX}" "${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ "$base" =~ ^${ADAPTER_ID_REGEX}-issue-([0-9]+)$ ]]; then
    printf '%s%s\n' "${ISSUE_SESSION_PREFIX}" "${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ "$base" =~ ^issue-([0-9]+)- ]]; then
    printf '%s%s\n' "${ISSUE_SESSION_PREFIX}" "${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ "$branch_ref" =~ ^refs/heads/${PR_WORKTREE_BRANCH_PREFIX_REGEX}-([0-9]+)- ]]; then
    printf '%s%s\n' "${PR_SESSION_PREFIX}" "${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ "$branch_ref" =~ ^refs/heads/${ISSUE_BRANCH_PREFIX_REGEX}-([0-9]+)- ]]; then
    printf '%s%s\n' "${ISSUE_SESSION_PREFIX}" "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

branch_name_is_managed() {
  local branch_name="${1:-}"
  local branch_glob=""

  for branch_glob in ${MANAGED_PR_BRANCH_GLOBS}; do
    case "$branch_name" in
      ${branch_glob}) return 0 ;;
    esac
  done

  return 1
}

is_legacy_automation_worktree() {
  local worktree_path="${1:-}"
  local branch_ref="${2:-}"
  local base

  base="$(basename "$worktree_path")"
  if [[ "$worktree_path" == "$WORKTREE_ROOT/"* ]]; then
    return 0
  fi
  case "$base" in
    ${ADAPTER_ID}-main-clean|${ADAPTER_ID}-pr-*|${ADAPTER_ID}-issue-*) return 0 ;;
  esac
  if [[ "$branch_ref" == refs/heads/* ]] && branch_name_is_managed "${branch_ref#refs/heads/}"; then
    return 0
  fi
  return 1
}

worktree_dirty() {
  local worktree_path="${1:-}"
  [[ -n "$(git -C "$worktree_path" status --short --untracked-files=normal)" ]]
}

worktree_has_active_owner() {
  local session_name="${1:-}"
  local status_output=""
  local status=""

  [[ -n "$session_name" ]] || return 1

  if tmux has-session -t "$session_name" 2>/dev/null; then
    return 0
  fi

  local run_dir="${RUNS_ROOT}/${session_name}"
  if [[ ! -d "$run_dir" ]]; then
    return 1
  fi

  # Completed workers still own their worktree until host-side reconcile
  # archives the run or writes reconciled.ok. Otherwise audit can delete the
  # worktree before publish/retry transitions consume it.
  if [[ ! -f "${run_dir}/reconciled.ok" ]]; then
    return 0
  fi

  status_output="$(
    bash "${BASH_SOURCE[0]%/*}/agent-project-worker-status" \
      --runs-root "$RUNS_ROOT" \
      --session "$session_name" 2>/dev/null || true
  )"
  status="$(awk -F= '/^STATUS=/{print $2}' <<<"$status_output" | tail -n 1)"
  [[ "$status" == "RUNNING" ]]
}

remove_legacy_worktree() {
  local worktree_path="${1:-}"
  local branch_ref="${2:-}"
  local branch_name=""

  git -C "$RETAINED_ROOT" worktree remove "$worktree_path" --force

  if [[ "$branch_ref" == refs/heads/* ]]; then
    branch_name="${branch_ref#refs/heads/}"
    if git -C "$RETAINED_ROOT" show-ref --verify --quiet "refs/heads/${branch_name}"; then
      git -C "$RETAINED_ROOT" branch -D "$branch_name" >/dev/null 2>&1 || true
    fi
  fi
}

issue_count=0
cleaned_count=0

current_worktree=""
current_branch_ref=""
current_head=""

while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ -z "$line" ]]; then
    if [[ -n "$current_worktree" ]]; then
      if [[ "$current_worktree" != "$RETAINED_ROOT" ]] && is_legacy_automation_worktree "$current_worktree" "$current_branch_ref"; then
        issue_count=$((issue_count + 1))
        session_name="$(session_for_worktree "$current_worktree" "$current_branch_ref" || true)"
        dirty="no"
        if worktree_dirty "$current_worktree"; then
          dirty="yes"
        fi
        active_owner="no"
        if worktree_has_active_owner "$session_name"; then
          active_owner="yes"
        fi

        printf 'RETAINED_WORKTREE=%s\n' "$current_worktree"
        printf 'BRANCH_REF=%s\n' "${current_branch_ref:-<detached>}"
        printf 'HEAD=%s\n' "${current_head:-<unknown>}"
        printf 'SESSION=%s\n' "${session_name:-<none>}"
        printf 'DIRTY=%s\n' "$dirty"
        printf 'ACTIVE_OWNER=%s\n' "$active_owner"

        if [[ "$cleanup" == "true" && "$dirty" == "no" && "$active_owner" == "no" ]]; then
          remove_legacy_worktree "$current_worktree" "$current_branch_ref"
          cleaned_count=$((cleaned_count + 1))
          printf 'CLEANUP=removed\n'
        else
          printf 'CLEANUP=skipped\n'
        fi
        printf '\n'
      fi

      current_worktree=""
      current_branch_ref=""
      current_head=""
    fi
    continue
  fi

  case "$line" in
    worktree\ *) current_worktree="${line#worktree }" ;;
    HEAD\ *) current_head="${line#HEAD }" ;;
    branch\ *) current_branch_ref="${line#branch }" ;;
  esac
done < <(git -C "$RETAINED_ROOT" worktree list --porcelain; printf '\n')

printf 'LEGACY_RETAINED_WORKTREE_COUNT=%s\n' "$issue_count"
printf 'LEGACY_RETAINED_WORKTREE_CLEANED=%s\n' "$cleaned_count"

if [[ "$strict" == "true" && "$issue_count" -gt 0 ]]; then
  exit 2
fi
