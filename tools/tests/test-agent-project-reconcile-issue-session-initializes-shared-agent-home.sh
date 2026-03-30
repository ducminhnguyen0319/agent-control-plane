#!/usr/bin/env bash
set -euo pipefail

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

shared_agent_home="$tmpdir/shared-agent-home"
shared_bin="$shared_agent_home/tools/bin"
shared_assets="$shared_agent_home/assets"
runs_root="$tmpdir/runs"
history_root="$tmpdir/history"
repo_root="$tmpdir/repo-root"
bin_dir="$tmpdir/bin"

mkdir -p "$shared_bin" "$shared_assets" "$runs_root/demo-issue-999" "$history_root" "$repo_root" "$bin_dir"
printf '{}\n' >"$shared_assets/workflow-catalog.json"

cp tools/bin/agent-project-reconcile-issue-session "$shared_bin/agent-project-reconcile-issue-session"
cp tools/bin/flow-shell-lib.sh "$shared_bin/flow-shell-lib.sh"
cp tools/bin/flow-config-lib.sh "$shared_bin/flow-config-lib.sh"
cp tools/bin/flow-resident-worker-lib.sh "$shared_bin/flow-resident-worker-lib.sh"

cat >"$shared_bin/agent-project-worker-status" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'SESSION=demo-issue-999\n'
printf 'STATUS=RUNNING\n'
printf 'META_FILE=%s\n' "$runs_root/demo-issue-999/run.env"
EOF

chmod +x \
  "$shared_bin/agent-project-reconcile-issue-session" \
  "$shared_bin/flow-shell-lib.sh" \
  "$shared_bin/flow-config-lib.sh" \
  "$shared_bin/flow-resident-worker-lib.sh" \
  "$shared_bin/agent-project-worker-status"

cat >"$runs_root/demo-issue-999/run.env" <<EOF
ISSUE_ID=999
WORKTREE=$tmpdir/issue-worktree
EOF

output="$(
  AGENT_CONTROL_PLANE_ROOT="$shared_agent_home" \
  bash "$shared_bin/agent-project-reconcile-issue-session" \
    --session demo-issue-999 \
    --repo-slug example/repo \
    --repo-root "$repo_root" \
    --runs-root "$runs_root" \
    --history-root "$history_root"
)"

[[ "$output" == *"STATUS=RUNNING"* ]]

echo "agent-project reconcile issue session initializes shared agent home test passed"
