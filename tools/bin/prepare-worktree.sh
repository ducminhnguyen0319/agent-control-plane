#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-config-lib.sh"

CONFIG_YAML="$(resolve_flow_config_yaml "${BASH_SOURCE[0]}")"
AGENT_REPO_ROOT="$(flow_resolve_agent_repo_root "${CONFIG_YAML}")"
CANONICAL_REPO_ROOT="$(flow_resolve_repo_root "${CONFIG_YAML}")"
DEFAULT_DEPENDENCY_SOURCE_ROOT="$CANONICAL_REPO_ROOT"
DEPENDENCY_SOURCE_ROOT="${ACP_DEPENDENCY_SOURCE_ROOT:-${F_LOSNING_DEPENDENCY_SOURCE_ROOT:-$DEFAULT_DEPENDENCY_SOURCE_ROOT}}"
SYNC_DEPENDENCY_BASELINE_SCRIPT="${ACP_SYNC_DEPENDENCY_BASELINE_SCRIPT:-${F_LOSNING_SYNC_DEPENDENCY_BASELINE_SCRIPT:-${SCRIPT_DIR}/sync-dependency-baseline.sh}}"
PACKAGE_MANAGER_BIN="${ACP_PACKAGE_MANAGER_BIN:-${F_LOSNING_PACKAGE_MANAGER_BIN:-pnpm}}"
LOCAL_WORKSPACE_INSTALL="${ACP_WORKTREE_LOCAL_INSTALL:-${F_LOSNING_WORKTREE_LOCAL_INSTALL:-false}}"
WORKTREE="${1:?usage: prepare-worktree.sh WORKTREE}"

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

link_shared_path() {
  local source_path="${1:?source path required}"
  local target_path="${2:?target path required}"

  [[ -e "$source_path" ]] || return 0
  if [[ -L "$target_path" ]]; then
    return 0
  fi
  if [[ -e "$target_path" ]]; then
    return 0
  fi

  mkdir -p "$(dirname "$target_path")"
  ln -s "$source_path" "$target_path"
}

dependency_source_ready() {
  local repo_root="${1:?repo root required}"
  local workspace_dir=""

  [[ -e "$repo_root/node_modules" ]] || return 1

  while IFS= read -r workspace_dir; do
    [[ -n "$workspace_dir" ]] || continue
    [[ -d "$workspace_dir" ]] || continue
    [[ -e "$workspace_dir/node_modules" ]] || return 1
  done < <(
    find "$repo_root/apps" -mindepth 1 -maxdepth 1 -type d 2>/dev/null || true
    find "$repo_root/packages" -mindepth 1 -maxdepth 1 -type d 2>/dev/null || true
  )
}

link_workspace_node_modules() {
  local dependency_root="${1:?dependency root required}"
  local worktree_root="${2:?worktree root required}"
  local workspace_dir=""
  local relative_path=""

  while IFS= read -r workspace_dir; do
    [[ -n "$workspace_dir" ]] || continue
    [[ -d "$workspace_dir/node_modules" ]] || continue
    relative_path="${workspace_dir#${dependency_root}/}"
    link_shared_path "$workspace_dir/node_modules" "$worktree_root/$relative_path/node_modules"
  done < <(
    find "$dependency_root/apps" -mindepth 1 -maxdepth 1 -type d 2>/dev/null || true
    find "$dependency_root/packages" -mindepth 1 -maxdepth 1 -type d 2>/dev/null || true
  )
}

configure_worktree_excludes() {
  local worktree="${1:?worktree required}"
  local exclude_file="${worktree}/.openclaw-artifacts/git-exclude"

  cat >"$exclude_file" <<'EOF'
node_modules
apps/*/node_modules
packages/*/node_modules
.openclaw-artifacts
.openclaw
SOUL.md
TOOLS.md
IDENTITY.md
USER.md
HEARTBEAT.md
BOOTSTRAP.md
.agent-session.env
EOF

  git -C "$worktree" config extensions.worktreeConfig true >/dev/null 2>&1 || true
  git -C "$worktree" config --worktree core.excludesFile "$exclude_file"
}

WORKTREE_REAL="$(realpath_safe "$WORKTREE")"
CANONICAL_REAL="$(realpath_safe "$CANONICAL_REPO_ROOT")"
DEPENDENCY_REAL="$(realpath_safe "$DEPENDENCY_SOURCE_ROOT")"

if [[ -n "$CANONICAL_REAL" && "$WORKTREE_REAL" == "$CANONICAL_REAL" ]]; then
  echo "refusing to prepare canonical checkout as worker worktree: $WORKTREE" >&2
  exit 1
fi

if [[ -n "$DEPENDENCY_REAL" && "$WORKTREE_REAL" == "$DEPENDENCY_REAL" ]]; then
  echo "refusing to prepare retained checkout as worker worktree: $WORKTREE" >&2
  exit 1
fi

mkdir -p "$WORKTREE/.openclaw-artifacts"
configure_worktree_excludes "$WORKTREE"

if [[ -x "$SYNC_DEPENDENCY_BASELINE_SCRIPT" && "$DEPENDENCY_REAL" == "$CANONICAL_REAL" ]]; then
  "$SYNC_DEPENDENCY_BASELINE_SCRIPT" >/dev/null
fi

if [[ "$LOCAL_WORKSPACE_INSTALL" == "true" ]]; then
  (
    cd "$WORKTREE"
    CI=1 "$PACKAGE_MANAGER_BIN" install --frozen-lockfile --prefer-offline
  )
else
  if ! dependency_source_ready "$DEPENDENCY_SOURCE_ROOT"; then
    echo "dependency source is missing required node_modules or built workspace artifacts: $DEPENDENCY_SOURCE_ROOT" >&2
    exit 1
  fi
  link_shared_path "$DEPENDENCY_SOURCE_ROOT/node_modules" "$WORKTREE/node_modules"
  link_workspace_node_modules "$DEPENDENCY_SOURCE_ROOT" "$WORKTREE"
fi

printf 'WORKTREE=%s\n' "$WORKTREE"
printf 'SANDBOX_ARTIFACT_DIR=%s\n' "$WORKTREE/.openclaw-artifacts"
