#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-config-lib.sh"

CONFIG_YAML="$(resolve_flow_config_yaml "${BASH_SOURCE[0]}")"
AGENT_REPO_ROOT="$(flow_resolve_agent_repo_root "${CONFIG_YAML}")"
CANONICAL_REPO_ROOT="$(flow_resolve_repo_root "${CONFIG_YAML}")"
AGENT_ROOT="$(flow_resolve_agent_root "${CONFIG_YAML}")"
STATE_ROOT="$(flow_resolve_state_root "${CONFIG_YAML}")"
LOCK_DIR="${STATE_ROOT}/dependency-baseline.lock"
PID_FILE="${LOCK_DIR}/pid"
HASH_FILE="${STATE_ROOT}/dependency-baseline.sha256"
PACKAGE_MANAGER_BIN="${ACP_PACKAGE_MANAGER_BIN:-${F_LOSNING_PACKAGE_MANAGER_BIN:-pnpm}}"
WORKSPACE_BUILD_PACKAGES_RAW="${ACP_WORKSPACE_BUILD_PACKAGES:-${F_LOSNING_WORKSPACE_BUILD_PACKAGES:-}}"
WORKSPACE_BUILD_ARTIFACTS_RAW="${ACP_WORKSPACE_BUILD_ARTIFACTS:-${F_LOSNING_WORKSPACE_BUILD_ARTIFACTS:-}}"
declare -a WORKSPACE_BUILD_PACKAGES=()
declare -a WORKSPACE_BUILD_ARTIFACTS=()

usage() {
  cat <<'USAGE'
Usage:
  sync-dependency-baseline.sh [--force]

Ensures the clean automation checkout has a current dependency baseline so
worker worktrees no longer need to borrow node_modules from the retained human
checkout.
USAGE
}

force="false"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) force="true"; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

realpath_safe() {
  local path_value="${1:-}"
  [[ -n "$path_value" ]] || return 1
  python3 - "$path_value" <<'PY'
import os
import sys
print(os.path.realpath(sys.argv[1]))
PY
}

split_list() {
  local raw="${1:-}"
  local item=""

  [[ -n "$raw" ]] || return 0
  while IFS= read -r item; do
    [[ -n "$item" ]] || continue
    printf '%s\n' "$item"
  done < <(tr ' ' '\n' <<<"$raw")
}

discover_workspace_build_packages() {
  local repo_root="${1:?repo root required}"
  python3 - "$repo_root" <<'PY'
from pathlib import Path
import json
import sys

repo_root = Path(sys.argv[1])
packages_root = repo_root / "packages"
if not packages_root.is_dir():
    raise SystemExit(0)

for package_json in sorted(packages_root.glob("*/package.json")):
    try:
        data = json.loads(package_json.read_text(encoding="utf-8"))
    except Exception:
        continue
    name = data.get("name")
    if isinstance(name, str) and name.strip():
        print(name.strip())
PY
}

load_workspace_lists() {
  local item=""

  WORKSPACE_BUILD_PACKAGES=()
  if [[ -n "$WORKSPACE_BUILD_PACKAGES_RAW" ]]; then
    while IFS= read -r item; do
      [[ -n "$item" ]] || continue
      WORKSPACE_BUILD_PACKAGES+=("$item")
    done < <(split_list "$WORKSPACE_BUILD_PACKAGES_RAW")
  else
    while IFS= read -r item; do
      [[ -n "$item" ]] || continue
      WORKSPACE_BUILD_PACKAGES+=("$item")
    done < <(discover_workspace_build_packages "$CANONICAL_REPO_ROOT")
  fi

  WORKSPACE_BUILD_ARTIFACTS=()
  if [[ -n "$WORKSPACE_BUILD_ARTIFACTS_RAW" ]]; then
    while IFS= read -r item; do
      [[ -n "$item" ]] || continue
      WORKSPACE_BUILD_ARTIFACTS+=("$item")
    done < <(split_list "$WORKSPACE_BUILD_ARTIFACTS_RAW")
  fi
}

compute_hash() {
  local repo_root="${1:?repo root required}"
  (
    cd "$repo_root"
    local files=()
    local candidate
    for candidate in package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc; do
      [[ -e "$candidate" ]] && files+=("$candidate")
    done
    {
      shasum -a 256 "${files[@]}"
      git rev-parse HEAD 2>/dev/null || true
    } | shasum -a 256 | awk '{print $1}'
  )
}

baseline_paths_ready() {
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

workspace_artifacts_ready() {
  local repo_root="${1:?repo root required}"
  local artifact=""

  if [[ "${#WORKSPACE_BUILD_ARTIFACTS[@]}" -eq 0 ]]; then
    return 0
  fi

  for artifact in "${WORKSPACE_BUILD_ARTIFACTS[@]}"; do
    [[ -f "${repo_root}/${artifact}" ]] || return 1
  done
}

build_workspace_artifacts() {
  local repo_root="${1:?repo root required}"
  local build_args=()
  local pkg=""

  if [[ "${#WORKSPACE_BUILD_PACKAGES[@]}" -eq 0 ]]; then
    return 0
  fi

  for pkg in "${WORKSPACE_BUILD_PACKAGES[@]}"; do
    build_args+=(--filter "$pkg")
  done

  (
    cd "$repo_root"
    CI=1 "$PACKAGE_MANAGER_BIN" "${build_args[@]}" build
  )
}

acquire_lock() {
  mkdir -p "$STATE_ROOT"
  while ! mkdir "$LOCK_DIR" 2>/dev/null; do
    if [[ -f "$PID_FILE" ]]; then
      local existing_pid
      existing_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
      if [[ -n "$existing_pid" ]] && ! kill -0 "$existing_pid" 2>/dev/null; then
        rm -rf "$LOCK_DIR"
        continue
      fi
    else
      rm -rf "$LOCK_DIR"
      continue
    fi
    sleep 1
  done
  printf '%s\n' "$$" >"$PID_FILE"
}

cleanup() {
  rm -rf "$LOCK_DIR"
}

trap cleanup EXIT

CANONICAL_REPO_ROOT="$(realpath_safe "$CANONICAL_REPO_ROOT")"
if [[ ! -d "$CANONICAL_REPO_ROOT/.git" && ! -f "$CANONICAL_REPO_ROOT/.git" ]]; then
  echo "canonical checkout is not a Git repo: $CANONICAL_REPO_ROOT" >&2
  exit 1
fi

if ! command -v "$PACKAGE_MANAGER_BIN" >/dev/null 2>&1; then
  echo "missing package manager: $PACKAGE_MANAGER_BIN" >&2
  exit 1
fi

load_workspace_lists
expected_hash="$(compute_hash "$CANONICAL_REPO_ROOT")"
current_hash="$(cat "$HASH_FILE" 2>/dev/null || true)"

if [[ "$force" != "true" && "$expected_hash" == "$current_hash" ]] && baseline_paths_ready "$CANONICAL_REPO_ROOT" && workspace_artifacts_ready "$CANONICAL_REPO_ROOT"; then
  printf 'DEPENDENCY_BASELINE=ready\n'
  printf 'REPO_ROOT=%s\n' "$CANONICAL_REPO_ROOT"
  printf 'HASH=%s\n' "$expected_hash"
  exit 0
fi

acquire_lock

load_workspace_lists
expected_hash="$(compute_hash "$CANONICAL_REPO_ROOT")"
current_hash="$(cat "$HASH_FILE" 2>/dev/null || true)"
if [[ "$force" != "true" && "$expected_hash" == "$current_hash" ]] && baseline_paths_ready "$CANONICAL_REPO_ROOT" && workspace_artifacts_ready "$CANONICAL_REPO_ROOT"; then
  printf 'DEPENDENCY_BASELINE=ready\n'
  printf 'REPO_ROOT=%s\n' "$CANONICAL_REPO_ROOT"
  printf 'HASH=%s\n' "$expected_hash"
  exit 0
fi

(
  cd "$CANONICAL_REPO_ROOT"
  CI=1 "$PACKAGE_MANAGER_BIN" install --frozen-lockfile --prefer-offline
)

build_workspace_artifacts "$CANONICAL_REPO_ROOT"

baseline_paths_ready "$CANONICAL_REPO_ROOT"
workspace_artifacts_ready "$CANONICAL_REPO_ROOT"
printf '%s\n' "$expected_hash" >"$HASH_FILE"

printf 'DEPENDENCY_BASELINE=updated\n'
printf 'REPO_ROOT=%s\n' "$CANONICAL_REPO_ROOT"
printf 'HASH=%s\n' "$expected_hash"
