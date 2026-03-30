#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SNAPSHOT_BIN="${FLOW_ROOT}/tools/bin/render-dashboard-snapshot.py"
SERVER_BIN="${FLOW_ROOT}/tools/bin/serve-dashboard.sh"
RUNTIMECTL_BIN="${FLOW_ROOT}/tools/bin/project-runtimectl.sh"

tmpdir="$(mktemp -d)"
server_pid=""
supervisor_pid=""
heartbeat_pid=""
shared_loop_pid=""
controller_pid=""
cleanup() {
  local pid=""
  for pid in "${server_pid}" "${shared_loop_pid}" "${controller_pid}" "${heartbeat_pid}" "${supervisor_pid}"; do
    [[ -n "${pid}" ]] || continue
    kill "${pid}" >/dev/null 2>&1 || true
    wait "${pid}" >/dev/null 2>&1 || true
  done
  rm -rf "${tmpdir}"
}
trap cleanup EXIT

profile_registry_root="${tmpdir}/profiles"
profile_dir="${profile_registry_root}/demo"
runs_root="${tmpdir}/runtime/demo/runs"
state_root="${tmpdir}/runtime/demo/state"
recurring_run_dir="${runs_root}/demo-issue-2"
scheduled_run_dir="${runs_root}/demo-issue-3"
recurring_worker_key="issue-lane-recurring-general-openclaw-safe"
scheduled_worker_key="issue-lane-scheduled-1800-openclaw-safe"
repo_slug="example/demo-control-plane"
port="18766"
heartbeat_child_pid_file="${tmpdir}/heartbeat-child.pid"
heartbeat_script="${tmpdir}/heartbeat-safe-auto.sh"
supervisor_script="${tmpdir}/project-runtime-supervisor.sh"
shared_loop_script="${tmpdir}/agent-project-heartbeat-loop"

mkdir -p \
  "${profile_dir}" \
  "${recurring_run_dir}" \
  "${scheduled_run_dir}" \
  "${state_root}/heartbeat-loop.lock" \
  "${state_root}/resident-workers/issues/2" \
  "${state_root}/resident-workers/issues/${recurring_worker_key}" \
  "${state_root}/resident-workers/issues/${scheduled_worker_key}" \
  "${state_root}/resident-workers/issue-queue/pending" \
  "${state_root}/retries/providers" \
  "${state_root}/scheduled-issues"

cat >"${profile_dir}/control-plane.yaml" <<EOF
schema_version: "1"
id: "demo"
repo:
  slug: "${repo_slug}"
  root: "${tmpdir}/repo"
  default_branch: "main"
runtime:
  orchestrator_agent_root: "${tmpdir}/runtime/demo"
  worktree_root: "${tmpdir}/worktrees"
  agent_repo_root: "${tmpdir}/repo"
  runs_root: "${runs_root}"
  state_root: "${state_root}"
  history_root: "${tmpdir}/runtime/demo/history"
  retained_repo_root: "${tmpdir}/repo"
  vscode_workspace_file: "${tmpdir}/demo.code-workspace"
session_naming:
  issue_prefix: "demo-issue-"
  pr_prefix: "demo-pr-"
execution:
  coding_worker: "openclaw"
  openclaw:
    model: "primary/model"
    thinking: "adaptive"
    timeout_seconds: 900
EOF

cat >"${recurring_run_dir}/run.env" <<EOF
TASK_KIND=issue
TASK_ID=2
SESSION=demo-issue-2
MODE=safe
STARTED_AT=2026-03-27T11:00:00Z
CODING_WORKER=openclaw
WORKTREE=${tmpdir}/worktrees/issue-2
BRANCH=agent/demo/issue-2
RESIDENT_WORKER_KEY=${recurring_worker_key}
OPENCLAW_MODEL=primary/model
EOF

cat >"${recurring_run_dir}/runner.env" <<'EOF'
RUNNER_STATE=succeeded
THREAD_ID=thread-demo-2
LAST_EXIT_CODE=0
LAST_FAILURE_REASON=''
UPDATED_AT=2026-03-27T11:03:00Z
EOF

cat >"${recurring_run_dir}/result.env" <<'EOF'
OUTCOME=implemented
ACTION=host-publish-issue-pr
EOF

cat >"${scheduled_run_dir}/run.env" <<EOF
TASK_KIND=issue
TASK_ID=3
SESSION=demo-issue-3
MODE=safe
STARTED_AT=2026-03-27T11:10:00Z
CODING_WORKER=openclaw
WORKTREE=${tmpdir}/worktrees/issue-3
BRANCH=agent/demo/issue-3
RESIDENT_WORKER_KEY=${scheduled_worker_key}
OPENCLAW_MODEL=primary/model
EOF

cat >"${scheduled_run_dir}/runner.env" <<'EOF'
RUNNER_STATE=succeeded
THREAD_ID=thread-demo-3
LAST_EXIT_CODE=0
LAST_FAILURE_REASON=''
UPDATED_AT=2026-03-27T11:12:00Z
EOF

cat >"${scheduled_run_dir}/result.env" <<'EOF'
OUTCOME=reported
ACTION=host-comment-scheduled-report
EOF

cat >"${heartbeat_script}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
sleep 60
EOF
chmod +x "${heartbeat_script}"

cat >"${supervisor_script}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
bash "${heartbeat_script}" >/dev/null 2>&1 &
child_pid=\$!
printf '%s\n' "\${child_pid}" >"${heartbeat_child_pid_file}"
wait "\${child_pid}"
EOF
chmod +x "${supervisor_script}"

cat >"${shared_loop_script}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
sleep 60
EOF
chmod +x "${shared_loop_script}"

bash "${supervisor_script}" >/dev/null 2>&1 &
supervisor_pid="$!"

for _ in $(seq 1 50); do
  if [[ -s "${heartbeat_child_pid_file}" ]]; then
    break
  fi
  sleep 0.1
done

heartbeat_pid="$(tr -d '[:space:]' <"${heartbeat_child_pid_file}")"
if [[ -z "${heartbeat_pid}" ]]; then
  echo "failed to capture heartbeat pid" >&2
  exit 1
fi

printf '%s\n' "${heartbeat_pid}" >"${state_root}/heartbeat-loop.lock/pid"
printf '%s\n' "${supervisor_pid}" >"${state_root}/runtime-supervisor.pid"

bash "${shared_loop_script}" --repo-slug "${repo_slug}" >/dev/null 2>&1 &
shared_loop_pid="$!"
printf '%s\n' "${shared_loop_pid}" >"${state_root}/shared-heartbeat-loop.pid"

sleep 60 >/dev/null 2>&1 &
controller_pid="$!"

cat >"${state_root}/resident-workers/issues/2/controller.env" <<EOF
ISSUE_ID=2
SESSION=demo-issue-2
CONTROLLER_PID=${controller_pid}
CONTROLLER_MODE=safe
CONTROLLER_LOOP_COUNT=4
CONTROLLER_STATE=waiting-provider
CONTROLLER_REASON=provider-cooldown
ACTIVE_RESIDENT_WORKER_KEY=${recurring_worker_key}
ACTIVE_RESIDENT_LANE_KIND=recurring
ACTIVE_RESIDENT_LANE_VALUE=general
ACTIVE_PROVIDER_BACKEND=openclaw
ACTIVE_PROVIDER_MODEL=primary/model
ACTIVE_PROVIDER_KEY=openclaw-primary-model
PROVIDER_SWITCH_COUNT=2
PROVIDER_FAILOVER_COUNT=1
PROVIDER_WAIT_COUNT=3
PROVIDER_WAIT_TOTAL_SECONDS=90
PROVIDER_LAST_WAIT_SECONDS=30
UPDATED_AT=2026-03-27T11:13:00Z
EOF

cat >"${state_root}/resident-workers/issues/${recurring_worker_key}/metadata.env" <<EOF
RESIDENT_WORKER_KIND=issue
RESIDENT_WORKER_SCOPE=lane
RESIDENT_WORKER_KEY=${recurring_worker_key}
RESIDENT_LANE_KIND=recurring
RESIDENT_LANE_VALUE=general
ISSUE_ID=2
CODING_WORKER=openclaw
TASK_COUNT=5
LAST_STATUS=SUCCEEDED
LAST_STARTED_AT=2026-03-27T11:00:00Z
LAST_FINISHED_AT=2026-03-27T11:03:00Z
LAST_RUN_SESSION=demo-issue-2
LAST_OUTCOME=implemented
LAST_ACTION=host-publish-issue-pr
LAST_FAILURE_REASON=
EOF

cat >"${state_root}/resident-workers/issues/${scheduled_worker_key}/metadata.env" <<EOF
RESIDENT_WORKER_KIND=issue
RESIDENT_WORKER_SCOPE=lane
RESIDENT_WORKER_KEY=${scheduled_worker_key}
RESIDENT_LANE_KIND=scheduled
RESIDENT_LANE_VALUE=1800
ISSUE_ID=3
CODING_WORKER=openclaw
TASK_COUNT=2
LAST_STATUS=SUCCEEDED
LAST_STARTED_AT=2026-03-27T11:10:00Z
LAST_FINISHED_AT=2026-03-27T11:12:00Z
LAST_RUN_SESSION=demo-issue-3
LAST_OUTCOME=reported
LAST_ACTION=host-comment-scheduled-report
LAST_FAILURE_REASON=
EOF

cat >"${state_root}/scheduled-issues/3.env" <<'EOF'
INTERVAL_SECONDS=1800
LAST_STARTED_AT=2026-03-27T11:10:00Z
NEXT_DUE_AT=2026-03-27T11:40:00Z
UPDATED_AT=2026-03-27T11:12:00Z
EOF

cat >"${state_root}/retries/providers/openclaw-primary-model.env" <<'EOF'
ATTEMPTS=2
NEXT_ATTEMPT_EPOCH=4102444800
NEXT_ATTEMPT_AT=2100-01-01T00:00:00Z
LAST_REASON=provider-quota-limit
UPDATED_AT=2026-03-27T11:13:00Z
EOF

cat >"${state_root}/resident-workers/issue-queue/pending/issue-6.env" <<'EOF'
ISSUE_ID=6
SESSION=demo-issue-6
UPDATED_AT=2026-03-27T11:13:30Z
EOF

snapshot_file="${tmpdir}/snapshot.json"
api_snapshot_file="${tmpdir}/api-snapshot.json"

ACP_PROFILE_REGISTRY_ROOT="${profile_registry_root}" python3 "${SNAPSHOT_BIN}" --pretty >"${snapshot_file}"

bash "${SERVER_BIN}" --host 127.0.0.1 --port "${port}" --registry-root "${profile_registry_root}" >"${tmpdir}/server.log" 2>&1 &
server_pid="$!"

for _ in $(seq 1 10); do
  if curl -fsS "http://127.0.0.1:${port}/api/snapshot.json" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

curl -fsS "http://127.0.0.1:${port}/api/snapshot.json" >"${api_snapshot_file}"
html="$(curl -fsS "http://127.0.0.1:${port}/")"

status_output="$(
  ACP_PROFILE_REGISTRY_ROOT="${profile_registry_root}" \
  ACP_PROJECT_RUNTIME_LAUNCHCTL_BIN="/nonexistent" \
    bash "${RUNTIMECTL_BIN}" status --profile-id demo
)"

grep -q '^RUNTIME_STATUS=running$' <<<"${status_output}"
grep -q "^HEARTBEAT_PID=${heartbeat_pid}$" <<<"${status_output}"
grep -q "^HEARTBEAT_PARENT_PID=${supervisor_pid}$" <<<"${status_output}"
grep -q "^SHARED_LOOP_PID=${shared_loop_pid}$" <<<"${status_output}"
grep -q "^SUPERVISOR_PID=${supervisor_pid}$" <<<"${status_output}"
grep -q '^CONTROLLER_COUNT=1$' <<<"${status_output}"

grep -q 'ACP Worker Dashboard' <<<"${html}"
grep -q 'Track active runs, resident controllers, queue pressure, and provider failover in one place.' <<<"${html}"

python3 - "${snapshot_file}" "${api_snapshot_file}" <<'PY'
import json
import sys

snapshot_path, api_path = sys.argv[1], sys.argv[2]
snapshot = json.load(open(snapshot_path, encoding="utf-8"))
api_snapshot = json.load(open(api_path, encoding="utf-8"))

assert snapshot["profile_count"] == 1
assert api_snapshot["profile_count"] == 1

profile = snapshot["profiles"][0]
api_profile = api_snapshot["profiles"][0]

assert profile["id"] == "demo"
assert profile["repo_slug"] == "example/demo-control-plane"
assert profile["counts"]["implemented_runs"] == 1
assert profile["counts"]["reported_runs"] == 1
assert profile["counts"]["blocked_runs"] == 0
assert profile["counts"]["live_resident_controllers"] == 1
assert profile["counts"]["resident_workers"] == 2
assert profile["counts"]["queued_issues"] == 1
assert profile["counts"]["provider_cooldowns"] == 1
assert profile["counts"]["scheduled_issues"] == 1

runs = {item["session"]: item for item in profile["runs"]}
assert runs["demo-issue-2"]["result_kind"] == "implemented"
assert runs["demo-issue-2"]["action"] == "host-publish-issue-pr"
assert runs["demo-issue-3"]["result_kind"] == "reported"
assert runs["demo-issue-3"]["action"] == "host-comment-scheduled-report"

controllers = {item["issue_id"]: item for item in profile["resident_controllers"]}
controller = controllers["2"]
assert controller["state"] == "waiting-provider"
assert controller["controller_live"] is True
assert controller["provider_failover_count"] == 1
assert controller["provider_wait_total_seconds"] == 90

workers = {item["key"]: item for item in profile["resident_workers"]}
assert workers["issue-lane-recurring-general-openclaw-safe"]["last_action"] == "host-publish-issue-pr"
assert workers["issue-lane-scheduled-1800-openclaw-safe"]["last_action"] == "host-comment-scheduled-report"

assert api_profile["counts"]["implemented_runs"] == 1
assert api_profile["counts"]["reported_runs"] == 1
assert api_profile["counts"]["live_resident_controllers"] == 1
assert api_profile["counts"]["scheduled_issues"] == 1
PY

echo "control plane dashboard runtime smoke test passed"
