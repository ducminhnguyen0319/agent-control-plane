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

mkdir -p "$shared_bin" "$shared_assets" "$runs_root/fl-pr-999" "$history_root" "$repo_root" "$bin_dir"
printf '{}\n' >"$shared_assets/workflow-catalog.json"

cp tools/bin/agent-project-reconcile-pr-session "$shared_bin/agent-project-reconcile-pr-session"
cp tools/bin/flow-shell-lib.sh "$shared_bin/flow-shell-lib.sh"
cp tools/bin/flow-config-lib.sh "$shared_bin/flow-config-lib.sh"

cat >"$shared_bin/agent-project-worker-status" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'SESSION=fl-pr-999\n'
printf 'STATUS=RUNNING\n'
printf 'META_FILE=%s\n' "$runs_root/fl-pr-999/run.env"
EOF

cat >"$bin_dir/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "pr" && "${2:-}" == "view" ]]; then
  printf '{"state":"OPEN","baseRefName":"main"}\n'
  exit 0
fi

echo "unexpected gh invocation: $*" >&2
exit 1
EOF

chmod +x \
  "$shared_bin/agent-project-reconcile-pr-session" \
  "$shared_bin/flow-shell-lib.sh" \
  "$shared_bin/flow-config-lib.sh" \
  "$shared_bin/agent-project-worker-status" \
  "$bin_dir/gh"

cat >"$runs_root/fl-pr-999/run.env" <<EOF
PR_NUMBER=999
WORKTREE=$tmpdir/pr-worktree
EOF

output="$(
  AGENT_CONTROL_PLANE_ROOT="$shared_agent_home" \
  PATH="$bin_dir:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  bash "$shared_bin/agent-project-reconcile-pr-session" \
    --session fl-pr-999 \
    --repo-slug example/repo \
    --repo-root "$repo_root" \
    --runs-root "$runs_root" \
    --history-root "$history_root"
)"

[[ "$output" == *"STATUS=RUNNING"* ]]
