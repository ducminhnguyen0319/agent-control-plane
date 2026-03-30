#!/usr/bin/env bash
set -euo pipefail

FLOW_TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="${FLOW_TOOLS_DIR%/bin}/tests"
TEST_TIMEOUT_SECONDS="${F_LOSNING_HEARTBEAT_PREFLIGHT_TEST_TIMEOUT_SECONDS:-120}"

run_with_timeout() {
  local timeout_seconds="${1:?timeout seconds required}"
  shift

  /opt/homebrew/bin/python3 - "$timeout_seconds" "$@" <<'PY'
import os
import signal
import subprocess
import sys

timeout_seconds = float(sys.argv[1])
argv = sys.argv[2:]

if not argv:
    sys.exit(64)

proc = subprocess.Popen(argv, start_new_session=True)
try:
    sys.exit(proc.wait(timeout=timeout_seconds))
except subprocess.TimeoutExpired:
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        proc.wait()
    sys.exit(124)
PY
}

run_preflight_test() {
  local label="${1:?label required}"
  local script_path="${2:?script path required}"
  local started_at

  started_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  printf '[%s] heartbeat preflight start name=%s\n' "$started_at" "$label"

  if run_with_timeout "$TEST_TIMEOUT_SECONDS" bash "$script_path"; then
    printf '[%s] heartbeat preflight end name=%s status=0\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$label"
    return 0
  fi

  local test_status=$?
  if [[ "$test_status" == "124" ]]; then
    printf 'HEARTBEAT_PREFLIGHT_TIMEOUT=%s\n' "$label"
  fi
  printf '[%s] heartbeat preflight end name=%s status=%s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$label" "$test_status"
  return "$test_status"
}

run_preflight_test "codex-recovery" "${TEST_DIR}/test-agent-project-codex-recovery.sh"
run_preflight_test "codex-quota-manager-failure-driven-rotation" "${TEST_DIR}/test-codex-quota-manager-failure-driven-rotation.sh"
run_preflight_test "codex-quota-wrapper" "${TEST_DIR}/test-codex-quota-wrapper.sh"
run_preflight_test "codex-quota-resolvers" "${TEST_DIR}/test-flow-resolve-codex-quota-tools.sh"
run_preflight_test "codex-live-thread-persist" "${TEST_DIR}/test-agent-project-codex-live-thread-persist.sh"
run_preflight_test "reconcile-failure-reason" "${TEST_DIR}/test-agent-project-reconcile-failure-reason.sh"
run_preflight_test "reconcile-pr-updated-branch-noop" "${TEST_DIR}/test-agent-project-reconcile-pr-updated-branch-noop.sh"
run_preflight_test "reconcile-pr-guard-blocked-no-commit" "${TEST_DIR}/test-agent-project-reconcile-pr-guard-blocked-no-commit.sh"
run_preflight_test "reconcile-pr-blocked-host-recovery" "${TEST_DIR}/test-agent-project-reconcile-pr-blocked-host-recovery.sh"
run_preflight_test "branch-verification-guard-targeted-coverage" "${TEST_DIR}/test-branch-verification-guard-targeted-coverage.sh"
run_preflight_test "branch-verification-guard-generated-artifacts" "${TEST_DIR}/test-branch-verification-guard-generated-artifacts.sh"
run_preflight_test "codex-session-wrapper" "${TEST_DIR}/test-agent-project-codex-session-wrapper.sh"
run_preflight_test "openclaw-session-wrapper" "${TEST_DIR}/test-agent-project-openclaw-session-wrapper.sh"
run_preflight_test "cleanup-session-orphan-fallback" "${TEST_DIR}/test-agent-project-cleanup-session-orphan-fallback.sh"
run_preflight_test "heartbeat-no-tmux-sessions" "${TEST_DIR}/test-heartbeat-safe-auto-no-tmux-sessions.sh"
run_preflight_test "heartbeat-static-capacity-without-quota-cache" "${TEST_DIR}/test-heartbeat-safe-auto-static-capacity-without-quota-cache.sh"
run_preflight_test "heartbeat-openclaw-skips-codex-quota" "${TEST_DIR}/test-heartbeat-safe-auto-openclaw-skips-codex-quota.sh"
run_preflight_test "heartbeat-empty-schedule-label-sync" "${TEST_DIR}/test-heartbeat-sync-issue-labels-empty-schedule.sh"
run_preflight_test "heartbeat-open-pr-terminal-sync" "${TEST_DIR}/test-heartbeat-sync-open-agent-prs-terminal-clears-running.sh"
run_preflight_test "heartbeat-pr-launch-dedup" "${TEST_DIR}/test-heartbeat-loop-pr-launch-dedup.sh"
run_preflight_test "heartbeat-auth-wait-capacity" "${TEST_DIR}/test-heartbeat-loop-auth-wait-does-not-consume-capacity.sh"
run_preflight_test "heartbeat-blocked-recovery-ready" "${TEST_DIR}/test-heartbeat-ready-issues-blocked-recovery.sh"
run_preflight_test "heartbeat-blocked-recovery-lane" "${TEST_DIR}/test-heartbeat-loop-blocked-recovery-lane.sh"
run_preflight_test "heartbeat-blocked-recovery-vs-pr-reservation" "${TEST_DIR}/test-heartbeat-loop-blocked-recovery-vs-pr-reservation.sh"
run_preflight_test "heartbeat-codex-pr-linked-issue-exclusion" "${TEST_DIR}/test-heartbeat-codex-pr-linked-issue-exclusion.sh"
run_preflight_test "create-follow-up-issue" "${TEST_DIR}/test-create-follow-up-issue.sh"
run_preflight_test "issue-local-workspace-install-policy" "${TEST_DIR}/test-issue-local-workspace-install-policy.sh"
run_preflight_test "issue-publish-scope-guard-docs-signal" "${TEST_DIR}/test-issue-publish-scope-guard-docs-signal.sh"
run_preflight_test "issue-before-blocked-hook" "${TEST_DIR}/test-agent-project-reconcile-issue-before-blocked.sh"
run_preflight_test "start-issue-worker-local-install-routing" "${TEST_DIR}/test-start-issue-worker-local-install-routing.sh"
run_preflight_test "start-issue-worker-blocked-context" "${TEST_DIR}/test-start-issue-worker-blocked-context.sh"
run_preflight_test "start-pr-fix-worker-host-blocker-context" "${TEST_DIR}/test-start-pr-fix-worker-host-blocker-context.sh"
run_preflight_test "run-codex-task-openclaw-routing" "${TEST_DIR}/test-run-codex-task-openclaw-routing.sh"
run_preflight_test "pr-risk-local-first-no-checks" "${TEST_DIR}/test-pr-risk-local-first-no-checks.sh"
run_preflight_test "pr-risk-fix-label-semantics" "${TEST_DIR}/test-pr-risk-fix-label-semantics.sh"
run_preflight_test "sync-pr-labels-fix-lane-uses-repair-queued" "${TEST_DIR}/test-sync-pr-labels-fix-lane-uses-repair-queued.sh"
run_preflight_test "audit-broken-worktree-cleanup" "${TEST_DIR}/test-audit-agent-worktrees-broken-worktree.sh"
run_preflight_test "audit-active-launch-skip" "${TEST_DIR}/test-audit-agent-worktrees-active-launch-skips-git-inspection.sh"
run_preflight_test "audit-pending-launch-owner" "${TEST_DIR}/test-audit-agent-worktrees-pending-launch-owner.sh"
run_preflight_test "audit-unreconciled-owner" "${TEST_DIR}/test-audit-agent-worktrees-unreconciled-owner.sh"

printf 'HEARTBEAT_PREFLIGHT_OK\n'
