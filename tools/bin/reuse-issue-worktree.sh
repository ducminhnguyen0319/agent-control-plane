#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-config-lib.sh"

usage() {
  cat <<'EOF'
Usage:
  reuse-issue-worktree.sh WORKTREE ISSUE_ID [SLUG]

Reset and re-branch an existing managed issue worktree so a recurring issue can
reuse the same workspace path across multiple cycles.
EOF
}

WORKTREE="${1:-}"
ISSUE_ID="${2:-}"
SLUG_INPUT="${3:-task}"

if [[ -z "${WORKTREE}" || -z "${ISSUE_ID}" ]]; then
  usage >&2
  exit 1
fi

FLOW_SKILL_DIR="$(resolve_flow_skill_dir "${BASH_SOURCE[0]}")"
if ! flow_require_explicit_profile_selection "${FLOW_SKILL_DIR}" "reuse-issue-worktree.sh"; then
  exit 64
fi

CONFIG_YAML="$(resolve_flow_config_yaml "${BASH_SOURCE[0]}")"
AGENT_REPO_ROOT="$(flow_resolve_agent_repo_root "${CONFIG_YAML}")"
ISSUE_BRANCH_PREFIX="$(flow_resolve_issue_branch_prefix "${CONFIG_YAML}")"
DEFAULT_BRANCH="$(flow_resolve_default_branch "${CONFIG_YAML}")"
BASE_REF="origin/${DEFAULT_BRANCH}"
PREPARE_SCRIPT="${SCRIPT_DIR}/prepare-worktree.sh"

safe_slug="$(printf '%s' "${SLUG_INPUT}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-')"
safe_slug="${safe_slug#-}"
safe_slug="${safe_slug%-}"
if [[ -z "${safe_slug}" ]]; then
  safe_slug="task"
fi

stamp="$(date +%Y%m%d-%H%M%S)"
branch_name="${ISSUE_BRANCH_PREFIX}-${ISSUE_ID}-${safe_slug}-${stamp}"
previous_branch="$(git -C "${WORKTREE}" branch --show-current 2>/dev/null || true)"
resolved_worktree=""
actual_branch=""

if ! git -C "${WORKTREE}" rev-parse --git-dir >/dev/null 2>&1; then
  echo "invalid managed worktree: ${WORKTREE}" >&2
  exit 1
fi

git -C "${AGENT_REPO_ROOT}" fetch \
  origin \
  "+refs/heads/${DEFAULT_BRANCH}:refs/remotes/origin/${DEFAULT_BRANCH}" \
  --prune >/dev/null

# Reset the resident workspace to the latest baseline before switching to the
# next focused cycle branch.
git -C "${WORKTREE}" reset --hard >/dev/null
git -C "${WORKTREE}" clean -fd >/dev/null
git -C "${WORKTREE}" checkout -B "${branch_name}" "${BASE_REF}" >/dev/null

if [[ -n "${previous_branch}" && "${previous_branch}" != "${branch_name}" ]]; then
  git -C "${AGENT_REPO_ROOT}" branch -D "${previous_branch}" >/dev/null 2>&1 || true
fi

"${PREPARE_SCRIPT}" "${WORKTREE}" >/dev/null

if ! git -C "${WORKTREE}" rev-parse --git-dir >/dev/null 2>&1; then
  echo "invalid managed worktree after reuse: ${WORKTREE}" >&2
  exit 1
fi

resolved_worktree="$(cd "${WORKTREE}" 2>/dev/null && pwd -P || true)"
if [[ -z "${resolved_worktree}" || ! -d "${resolved_worktree}" ]]; then
  echo "reused worktree path is unavailable: ${WORKTREE}" >&2
  exit 1
fi

if ! git -C "${AGENT_REPO_ROOT}" worktree list --porcelain | grep -Fqx "worktree ${resolved_worktree}"; then
  echo "reused worktree is no longer registered: ${resolved_worktree}" >&2
  exit 1
fi

actual_branch="$(git -C "${WORKTREE}" branch --show-current 2>/dev/null || true)"
if [[ -z "${actual_branch}" || "${actual_branch}" != "${branch_name}" ]]; then
  echo "reused worktree branch mismatch: expected ${branch_name} got ${actual_branch:-<none>}" >&2
  exit 1
fi

printf 'WORKTREE=%s\n' "${WORKTREE}"
printf 'BRANCH=%s\n' "${branch_name}"
printf 'BASE_REF=%s\n' "${BASE_REF}"
printf 'REUSED=yes\n'
