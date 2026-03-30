#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SERVER_BIN="${FLOW_ROOT}/tools/bin/serve-dashboard.sh"

tmpdir="$(mktemp -d)"
server_pid=""
cleanup() {
  if [[ -n "${server_pid}" ]]; then
    kill "${server_pid}" >/dev/null 2>&1 || true
    wait "${server_pid}" >/dev/null 2>&1 || true
  fi
  rm -rf "$tmpdir"
}
trap cleanup EXIT

profile_registry_root="$tmpdir/profiles"
profile_dir="$profile_registry_root/demo"
runs_root="$tmpdir/runtime/demo/runs"
state_root="$tmpdir/runtime/demo/state"
run_dir="$runs_root/demo-issue-1"
port="18765"

mkdir -p "$profile_dir" "$run_dir" "$state_root"

cat >"$profile_dir/control-plane.yaml" <<EOF
schema_version: "1"
id: "demo"
repo:
  slug: "example/demo-dashboard"
  root: "$tmpdir/repo"
  default_branch: "main"
runtime:
  orchestrator_agent_root: "$tmpdir/runtime/demo"
  worktree_root: "$tmpdir/worktrees"
  agent_repo_root: "$tmpdir/repo"
  runs_root: "$runs_root"
  state_root: "$state_root"
  history_root: "$tmpdir/runtime/demo/history"
  retained_repo_root: "$tmpdir/repo"
  vscode_workspace_file: "$tmpdir/demo.code-workspace"
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

cat >"$run_dir/run.env" <<'EOF'
TASK_KIND=issue
TASK_ID=1
SESSION=demo-issue-1
MODE=safe
STARTED_AT=2026-03-26T15:00:00Z
CODING_WORKER=openclaw
EOF

cat >"$run_dir/runner.env" <<'EOF'
RUNNER_STATE=succeeded
THREAD_ID=thread-demo-1
LAST_EXIT_CODE=0
UPDATED_AT=2026-03-26T15:01:00Z
EOF

cat >"$run_dir/result.env" <<'EOF'
OUTCOME=implemented
ACTION=host-publish-issue-pr
EOF

bash "$SERVER_BIN" --host 127.0.0.1 --port "$port" --registry-root "$profile_registry_root" >"$tmpdir/server.log" 2>&1 &
server_pid="$!"

for _ in 1 2 3 4 5 6 7 8 9 10; do
  if curl -fsS "http://127.0.0.1:${port}/api/snapshot.json" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

snapshot="$(curl -fsS "http://127.0.0.1:${port}/api/snapshot.json")"
html="$(curl -fsS "http://127.0.0.1:${port}/")"

grep -q '"profile_count": 1' <<<"$snapshot"
grep -q '"id": "demo"' <<<"$snapshot"
grep -q 'ACP Worker Dashboard' <<<"$html"
grep -q 'Lifecycle shows whether a worker session finished cleanly' <<<"$html"

echo "serve dashboard test passed"
