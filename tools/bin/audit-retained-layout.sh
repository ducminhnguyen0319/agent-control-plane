#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-config-lib.sh"

CONFIG_YAML="$(resolve_flow_config_yaml "${BASH_SOURCE[0]}")"
RETAINED_ROOT="$(flow_resolve_retained_repo_root "${CONFIG_YAML}")"
ADAPTER_ID="$(flow_resolve_adapter_id "${CONFIG_YAML}")"

classify_worktree() {
  local path="${1:-}"
  case "$path" in
    */${ADAPTER_ID}-pr-*|*/${ADAPTER_ID}-issue-*|*/${ADAPTER_ID}-main-clean)
      printf 'legacy-automation\n'
      ;;
    "$RETAINED_ROOT")
      printf 'retained-main\n'
      ;;
    *)
      printf 'retained-manual\n'
      ;;
  esac
}

count_dirty_paths() {
  local path="${1:?path required}"
  git -C "$path" status --porcelain 2>/dev/null | wc -l | tr -d ' '
}

current_branch() {
  local path="${1:?path required}"
  git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null || printf 'unknown\n'
}

current_head() {
  local path="${1:?path required}"
  git -C "$path" rev-parse --short HEAD 2>/dev/null || printf 'unknown\n'
}

worktree_list="$(
  git -C "$RETAINED_ROOT" worktree list --porcelain |
    awk '/^worktree /{print substr($0,10)}'
)"

printf 'RETAINED_ROOT=%s\n' "$RETAINED_ROOT"
printf 'RETAINED_WORKTREE_COUNT=%s\n' "$(printf '%s\n' "$worktree_list" | sed '/^$/d' | wc -l | tr -d ' ')"

while IFS= read -r worktree; do
  [[ -n "$worktree" ]] || continue
  printf '\n[worktree]\n'
  printf 'path=%s\n' "$worktree"
  printf 'class=%s\n' "$(classify_worktree "$worktree")"
  printf 'branch=%s\n' "$(current_branch "$worktree")"
  printf 'head=%s\n' "$(current_head "$worktree")"
  printf 'dirty_paths=%s\n' "$(count_dirty_paths "$worktree")"
done <<<"$worktree_list"
