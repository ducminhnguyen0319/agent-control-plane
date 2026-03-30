#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-config-lib.sh"

WORKER_STATUS_TOOL="${BASH_SOURCE[0]%/*}/agent-project-worker-status"
WORKTREE_CLEANUP_TOOL="${BASH_SOURCE[0]%/*}/agent-cleanup-worktree"
CONFIG_YAML="$(resolve_flow_config_yaml "${BASH_SOURCE[0]}")"
AGENT_REPO_ROOT="$(flow_resolve_agent_repo_root "${CONFIG_YAML}")"
WORKTREE_ROOT="$(flow_resolve_worktree_root "${CONFIG_YAML}")"
AGENT_ROOT="$(flow_resolve_agent_root "${CONFIG_YAML}")"
RUNS_ROOT="$(flow_resolve_runs_root "${CONFIG_YAML}")"
PENDING_LAUNCH_DIR="${ACP_PENDING_LAUNCH_DIR:-${F_LOSNING_PENDING_LAUNCH_DIR:-$(flow_resolve_state_root "${CONFIG_YAML}")/pending-launches}}"
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
  audit-agent-worktrees.sh [--cleanup] [--strict]

Audits agent-managed worktrees attached to the anchor repo and removes stale
ones when they no longer have a running owner and only contain generated
artifacts such as node_modules symlinks or .openclaw-artifacts.

Options:
  --cleanup  Remove clean/orphaned agent worktrees automatically.
  --strict   Exit non-zero when any stale agent worktree is found.
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

if [[ ! -d "$AGENT_REPO_ROOT/.git" && ! -f "$AGENT_REPO_ROOT/.git" ]]; then
  echo "agent repo root is not a Git checkout: $AGENT_REPO_ROOT" >&2
  exit 1
fi

session_for_worktree() {
  local worktree_path="${1:-}"
  local branch_ref="${2:-}"
  local base

  base="$(basename "$worktree_path")"
  if [[ "$base" =~ ^pr-([0-9]+)- ]]; then
    printf '%s%s\n' "${PR_SESSION_PREFIX}" "${BASH_REMATCH[1]}"
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

is_agent_managed_worktree() {
  local worktree_path="${1:-}"
  local branch_ref="${2:-}"
  local branch_name=""

  [[ "$worktree_path" == "$WORKTREE_ROOT/"* ]] || return 1
  if [[ "$branch_ref" == refs/heads/* ]]; then
    branch_name="${branch_ref#refs/heads/}"
    if branch_name_is_managed "$branch_name"; then
      return 0
    fi
  fi
  case "$(basename "$worktree_path")" in
    pr-*|issue-*|shared-*) return 0 ;;
  esac
  return 1
}

worktree_effectively_dirty() {
  local worktree_path="${1:?worktree path required}"
  local filtered=""

  if ! git -C "$worktree_path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    return 1
  fi

  filtered="$(
    git -C "$worktree_path" status --short --untracked-files=normal \
      | awk '
          /^\?\? node_modules$/ {next}
          /^\?\? .+\/node_modules$/ {next}
          /^\?\? \.openclaw-artifacts$/ {next}
          /^\?\? \.openclaw-artifacts\// {next}
          {print}
        '
  )"
  [[ -n "$filtered" ]]
}

worktree_is_broken() {
  local worktree_path="${1:?worktree path required}"
  [[ -d "$worktree_path" ]] || return 0
  git -C "$worktree_path" rev-parse --is-inside-work-tree >/dev/null 2>&1 && return 1
  return 0
}

worktree_has_active_owner() {
  local session_name="${1:-}"
  local run_dir=""
  local status_output=""
  local status=""

  [[ -n "$session_name" ]] || return 1

  if tmux has-session -t "$session_name" 2>/dev/null; then
    return 0
  fi

  run_dir="${RUNS_ROOT}/${session_name}"
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
    "$WORKER_STATUS_TOOL" \
      --runs-root "$RUNS_ROOT" \
      --session "$session_name" 2>/dev/null || true
  )"
  status="$(awk -F= '/^STATUS=/{print $2}' <<<"$status_output" | tail -n 1)"
  [[ "$status" == "RUNNING" ]]
}

worktree_has_active_launch() {
  local session_name="${1:-}"
  local pending_file=""
  local pending_pid=""

  [[ -n "$session_name" ]] || return 1

  case "$session_name" in
    "${ISSUE_SESSION_PREFIX}"*)
      pending_file="${PENDING_LAUNCH_DIR}/issue-${session_name#${ISSUE_SESSION_PREFIX}}.pid"
      ;;
    "${PR_SESSION_PREFIX}"*)
      pending_file="${PENDING_LAUNCH_DIR}/pr-${session_name#${PR_SESSION_PREFIX}}.pid"
      ;;
    *)
      return 1
      ;;
  esac

  [[ -f "$pending_file" ]] || return 1
  pending_pid="$(tr -d '[:space:]' <"$pending_file" 2>/dev/null || true)"
  [[ -n "$pending_pid" ]] || return 1
  kill -0 "$pending_pid" 2>/dev/null
}

remove_agent_worktree() {
  local worktree_path="${1:-}"
  local branch_ref="${2:-}"
  local branch_name=""
  local cleanup_args=()
  local cleanup_failed="false"

  if [[ "$branch_ref" == refs/heads/* ]]; then
    branch_name="${branch_ref#refs/heads/}"
    cleanup_args=(--branch "$branch_name" --path "$worktree_path" --allow-unmerged)
    if [[ "$branch_name" == "${ISSUE_BRANCH_PREFIX}"-* ]]; then
      cleanup_args+=(--keep-remote)
    fi
    if ! (
      cd "$AGENT_REPO_ROOT"
      "$WORKTREE_CLEANUP_TOOL" "${cleanup_args[@]}"
    ) >/dev/null 2>&1; then
      cleanup_failed="true"
    fi
  else
    git -C "$AGENT_REPO_ROOT" worktree remove "$worktree_path" --force || true
    git -C "$AGENT_REPO_ROOT" worktree prune
    return 0
  fi

  if [[ "$cleanup_failed" == "true" ]]; then
    rm -rf "$worktree_path"
    if [[ -n "$branch_name" ]]; then
      git -C "$AGENT_REPO_ROOT" branch -D "$branch_name" >/dev/null 2>&1 || true
    fi
  fi

  git -C "$AGENT_REPO_ROOT" worktree prune >/dev/null 2>&1 || true
}

issue_count=0
cleaned_count=0

current_worktree=""
current_branch_ref=""
current_head=""

while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ -z "$line" ]]; then
    if [[ -n "$current_worktree" ]]; then
      if [[ "$current_worktree" != "$AGENT_REPO_ROOT" ]] && is_agent_managed_worktree "$current_worktree" "$current_branch_ref"; then
        session_name="$(session_for_worktree "$current_worktree" "$current_branch_ref" || true)"
        active_owner="no"
        if worktree_has_active_owner "$session_name"; then
          active_owner="yes"
        fi
        active_launch="no"
        if worktree_has_active_launch "$session_name"; then
          active_launch="yes"
        fi

        if [[ "$active_owner" == "yes" || "$active_launch" == "yes" ]]; then
          current_worktree=""
          current_branch_ref=""
          current_head=""
          continue
        fi

        broken_worktree="no"
        if worktree_is_broken "$current_worktree"; then
          broken_worktree="yes"
        fi
        dirty="no"
        if [[ "$broken_worktree" == "no" ]] && worktree_effectively_dirty "$current_worktree"; then
          dirty="yes"
        fi

        issue_count=$((issue_count + 1))

        printf 'AGENT_WORKTREE=%s\n' "$current_worktree"
        printf 'BRANCH_REF=%s\n' "${current_branch_ref:-<detached>}"
        printf 'HEAD=%s\n' "${current_head:-<unknown>}"
        printf 'SESSION=%s\n' "${session_name:-<none>}"
        printf 'BROKEN_WORKTREE=%s\n' "$broken_worktree"
        printf 'DIRTY=%s\n' "$dirty"
        printf 'ACTIVE_OWNER=%s\n' "$active_owner"
        printf 'ACTIVE_LAUNCH=%s\n' "$active_launch"

        if [[ "$cleanup" == "true" && "$dirty" == "no" && "$active_owner" == "no" && "$active_launch" == "no" ]]; then
          remove_agent_worktree "$current_worktree" "$current_branch_ref"
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
done < <(git -C "$AGENT_REPO_ROOT" worktree list --porcelain; printf '\n')

printf 'LEGACY_AGENT_WORKTREE_COUNT=%s\n' "$issue_count"
printf 'LEGACY_AGENT_WORKTREE_CLEANED=%s\n' "$cleaned_count"

if [[ "$strict" == "true" && "$issue_count" -gt 0 ]]; then
  exit 2
fi
