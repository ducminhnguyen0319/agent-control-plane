#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKER_STATUS_TOOL="${FLOW_ROOT}/tools/bin/agent-project-worker-status"

tmpdir="$(mktemp -d)"
cleanup() { rm -rf "${tmpdir}"; }
trap cleanup EXIT

session="test-crash-1"
runs_root="${tmpdir}/runs"
session_log="${runs_root}/${session}/${session}.log"
runner_state_file="${runs_root}/${session}/runner.env"
result_file="${runs_root}/${session}/result.env"
run_env="${runs_root}/${session}/run.env"

mkdir -p "${runs_root}/${session}"

# Minimal run.env
cat >"$run_env" <<EOF
SESSION=${session}
TASK_KIND=issue
TASK_ID=99
EOF

# Helper to assert STATUS value
assert_status() {
  local expected="${1:?expected status required}"
  local actual
  actual="$(bash "${WORKER_STATUS_TOOL}" --runs-root "${runs_root}" --session "${session}" | awk -F= '/^STATUS=/{print $2}')"
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: expected STATUS=${expected} but got STATUS=${actual}" >&2
    return 1
  fi
  printf .
}

assert_failure_reason() {
  local expected="${1:?expected reason required}"
  local actual
  actual="$(bash "${WORKER_STATUS_TOOL}" --runs-root "${runs_root}" --session "${session}" | awk -F= '/^FAILURE_REASON=/{print $2}')"
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: expected FAILURE_REASON=${expected} but got FAILURE_REASON=${actual}" >&2
    return 1
  fi
  printf .
}

# ============================================================
# Test 1: Runner still running, tmux gone → FAILED (crash)
# This is the primary bug: without the fix, a stale result.env
# from a prior cycle would cause SUCCEEDED instead.
# ============================================================

# Simulate a previous cycle that wrote result.env
cat >"$result_file" <<'EOF'
OUTCOME=implemented
ACTION=host-publish-issue-pr
EOF

# Simulate runner that crashed mid-cycle (still marked running).
# When LAST_FAILURE_REASON is already set, worker-status preserves it;
# when empty it falls back to runner-aborted-before-completion.
cat >"$runner_state_file" <<'EOF'
RUNNER_STATE=running
THREAD_ID=some-thread
ATTEMPT=1
RESUME_COUNT=0
LAST_EXIT_CODE=1
LAST_FAILURE_REASON=""
LAST_TRIGGER_REASON=schedule
UPDATED_AT=2025-01-01T00:00:00Z
EOF

# No exit marker in log
: >"$session_log"

assert_status "FAILED"
assert_failure_reason "runner-aborted-before-completion"

# ============================================================
# Test 2: Runner crashed with waiting-auth-refresh → FAILED
# ============================================================

cat >"$runner_state_file" <<'EOF'
RUNNER_STATE=waiting-auth-refresh
THREAD_ID=auth-thread
ATTEMPT=2
RESUME_COUNT=0
LAST_EXIT_CODE=
LAST_FAILURE_REASON=""
LAST_TRIGGER_REASON=schedule
UPDATED_AT=2025-01-01T00:00:00Z
EOF

assert_status "FAILED"
assert_failure_reason "runner-aborted-before-completion"

# ============================================================
# Test 3: Runner crashed with switching-account → FAILED
# ============================================================

cat >"$runner_state_file" <<'EOF'
RUNNER_STATE=switching-account
THREAD_ID=switch-thread
ATTEMPT=1
RESUME_COUNT=0
LAST_EXIT_CODE=0
LAST_FAILURE_REASON=""
LAST_TRIGGER_REASON=schedule
UPDATED_AT=2025-01-01T00:00:00Z
EOF

assert_status "FAILED"

# ============================================================
# Test 4: Running runner with explicit Codex stall marker recovers real reason
# ============================================================

cat >"$runner_state_file" <<'EOF'
RUNNER_STATE=running
THREAD_ID=stall-thread
ATTEMPT=1
RESUME_COUNT=0
LAST_EXIT_CODE=
LAST_FAILURE_REASON=""
LAST_TRIGGER_REASON=schedule
UPDATED_AT=2025-01-01T00:00:00Z
EOF

cat >"$session_log" <<'EOF'
[2026-01-01T00:00:00Z] starting Codex exec attempt 1
{"type":"thread.started","thread_id":"stall-thread"}
{"type":"turn.started"}
[2026-01-01T00:05:00Z] stale-run no-codex-progress-before-stall-threshold elapsed=300s idle=300s
EOF

assert_status "FAILED"
assert_failure_reason "no-codex-progress-before-stall-threshold"

# ============================================================
# Test 5: Running runner with startup-only trace recovers Codex startup stall
# ============================================================

cat >"$runner_state_file" <<'EOF'
RUNNER_STATE=running
THREAD_ID=startup-thread
ATTEMPT=1
RESUME_COUNT=0
LAST_EXIT_CODE=
LAST_FAILURE_REASON=""
LAST_TRIGGER_REASON=schedule
UPDATED_AT=2025-01-01T00:00:00Z
EOF

cat >"$session_log" <<'EOF'
{"type":"thread.started","thread_id":"startup-thread"}
{"type":"turn.started"}
EOF

assert_status "FAILED"
assert_failure_reason "no-codex-progress-before-stall-threshold"

# ============================================================
# Test 6: Runner succeeded (normal path unchanged)
# ============================================================

# Remove stale state
rm -f "$result_file"

cat >"$runner_state_file" <<'EOF'
RUNNER_STATE=succeeded
THREAD_ID=ok-thread
ATTEMPT=1
RESUME_COUNT=0
LAST_EXIT_CODE=0
LAST_FAILURE_REASON=""
LAST_TRIGGER_REASON=schedule
UPDATED_AT=2025-01-01T00:00:00Z
EOF

assert_status "SUCCEEDED"

# ============================================================
# Test 7: Runner failed (normal path unchanged)
# ============================================================

cat >"$runner_state_file" <<'EOF'
RUNNER_STATE=failed
THREAD_ID=fail-thread
ATTEMPT=1
RESUME_COUNT=0
LAST_EXIT_CODE=42
LAST_FAILURE_REASON=syntax-error
LAST_TRIGGER_REASON=schedule
UPDATED_AT=2025-01-01T00:00:00Z
EOF

assert_status "FAILED"
assert_failure_reason "syntax-error"

# ============================================================
# Test 8: Unknown state with stale result.env and no runner crash
# → SUCCEEDED via result.env (still works for valid completions)
# ============================================================

rm -f "$runner_state_file"
: >"$session_log"

cat >"$result_file" <<'EOF'
OUTCOME=implemented
ACTION=host-publish-issue-pr
EOF

assert_status "SUCCEEDED"
out="$(bash "${WORKER_STATUS_TOOL}" --runs-root "${runs_root}" --session "${session}")"
if ! grep -q 'RESULT_ONLY_COMPLETION=yes' <<<"$out"; then
  echo "FAIL: expected RESULT_ONLY_COMPLETION=yes" >&2
  exit 1
fi

echo ""
echo "worker-status crash detection tests passed"
