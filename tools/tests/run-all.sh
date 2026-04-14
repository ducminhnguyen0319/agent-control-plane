#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$FLOW_ROOT"

current_test=""
trap 'rc=$?; if [[ $rc -ne 0 && -n "$current_test" ]]; then printf "FAILED_TEST=%s\n" "$current_test" >&2; fi; exit "$rc"' EXIT

tests=(
  tools/tests/test-agent-control-plane-npm-cli.sh
  tools/tests/test-agent-control-plane-setup-gitea-dry-run-without-gh.sh
  tools/tests/test-agent-project-detached-launch-stable-cwd.sh
  tools/tests/test-agent-project-claude-session-wrapper-reaps-child-on-term.sh
  tools/tests/test-agent-project-claude-session-wrapper-does-not-retry-provider-quota.sh
  tools/tests/test-agent-project-run-codex-resilient-uses-path-python-and-gnu-stat.sh
  tools/tests/test-agent-project-run-codex-resilient-sets-npm-cache.sh
  tools/tests/test-agent-project-sync-source-repo-main.sh
  tools/tests/test-heartbeat-safe-auto-uses-path-python.sh
  tools/tests/test-heartbeat-safe-auto-skips-self-sync.sh
  tools/tests/test-heartbeat-safe-auto-flushes-github-outbox.sh
  tools/tests/test-heartbeat-safe-auto-syncs-source-repo-main.sh
  tools/tests/test-agent-project-catch-up-terminal-prs-defaults-closed-hook.sh
  tools/tests/test-flow-github-graphql-availability-schedules-core-rate-limit-cooldown.sh
  tools/tests/test-flow-github-api-repo-reacts-to-core-rate-limit.sh
  tools/tests/test-flow-git-remote-repo-slug-gitea.sh
  tools/tests/test-flow-gitea-issue-read-adapter.sh
  tools/tests/test-flow-gitea-issue-write-adapter.sh
  tools/tests/test-flow-gitea-pr-adapter.sh
  tools/tests/test-flow-gitea-public-read-without-auth.sh
  tools/tests/test-heartbeat-hooks-local-mirror-fallback.sh
  tools/tests/test-agent-github-update-labels-enqueues-outbox.sh
  tools/tests/test-github-write-outbox-flushes-issue-comment.sh
  tools/tests/test-github-write-outbox-flushes-pr-approval.sh
  tools/tests/test-agent-project-reconcile-issue-session-enqueues-comment-outbox.sh
  tools/tests/test-agent-project-reconcile-pr-session-enqueues-comment-outbox.sh
  tools/tests/test-agent-project-codex-session-wrapper-prefers-path-codex.sh
  tools/tests/test-agent-project-codex-session-wrapper-recovers-var-tmp-logged-artifacts.sh
  tools/tests/test-agent-project-cleanup-session-removes-registered-worktree-without-rg.sh
  tools/tests/test-agent-project-cleanup-session-propagates-failure-with-session.sh
  tools/tests/test-cleanup-worktree-syncs-workspace-after-cleanup-failure.sh
  tools/tests/test-resident-issue-queue-status-contract.sh
  tools/tests/test-agent-project-reconcile-issue-provider-quota-schedules-provider-cooldown.sh
  tools/tests/test-agent-project-reconcile-issue-session-warns-on-cleanup-failure.sh
  tools/tests/test-agent-project-reconcile-pr-session-warns-on-cleanup-failure.sh
  tools/tests/test-agent-project-reconcile-pr-skips-host-action-while-github-core-rate-limited.sh
  tools/tests/test-agent-project-reconcile-pr-rate-limit-retries-host-action.sh
  tools/tests/test-pr-reconcile-hooks-refreshes-recurring-issue-checklist.sh
  tools/tests/test-pr-risk-gitea-forge-view.sh
  tools/tests/test-start-pr-fix-worker-gitea-comments-fallback.sh
  tools/tests/test-start-pr-fix-worker-uses-source-sync-remote.sh
  tools/tests/test-scaffold-profile-gitea-runtime-env.sh
  tools/tests/test-dashboard-snapshot-includes-github-outbox.sh
  tools/tests/test-issue-reconcile-hooks-kick-scheduler-uses-profile.sh
  tools/tests/test-profile-adopt-skip-anchor-sync-creates-agent-repo-root.sh
  tools/tests/test-vendored-codex-quota-claude-oauth-only.sh
  tools/tests/test-package-smoke-command.sh
)

for ((i = 0; i < ${#tests[@]}; i += 1)); do
  current_test="${tests[$i]}"
  printf '[%s/%s] %s\n' "$((i + 1))" "${#tests[@]}" "${tests[$i]}"
  bash "${tests[$i]}"
done
