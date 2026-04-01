#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PR_RECONCILE_SRC="${FLOW_ROOT}/tools/bin/agent-project-reconcile-pr-session"
FLOW_SHELL_LIB="${FLOW_ROOT}/tools/bin/flow-shell-lib.sh"
FLOW_CONFIG_LIB="${FLOW_ROOT}/tools/bin/flow-config-lib.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

shared_agent_home="$tmpdir/shared-agent-home"
shared_bin="$shared_agent_home/tools/bin"
shared_assets="$shared_agent_home/assets"
runs_root="$tmpdir/runs"
history_root="$tmpdir/history"
bin_dir="$tmpdir/bin"

mkdir -p "$shared_bin" "$shared_assets" "$runs_root/fl-pr-303" "$history_root" "$bin_dir"

cp "$PR_RECONCILE_SRC" "$shared_bin/agent-project-reconcile-pr-session"
cp "$FLOW_SHELL_LIB" "$shared_bin/flow-shell-lib.sh"
cp "$FLOW_CONFIG_LIB" "$shared_bin/flow-config-lib.sh"
printf '{}\n' >"$shared_assets/workflow-catalog.json"

cat >"$shared_bin/agent-project-worker-status" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'SESSION=fl-pr-303\n'
printf 'STATUS=FAILED\n'
printf 'META_FILE=%s\n' "$runs_root/fl-pr-303/run.env"
EOF

cat >"$bin_dir/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "gh should not be called for stale reconcile guard" >&2
exit 1
EOF

chmod +x \
  "$shared_bin/agent-project-reconcile-pr-session" \
  "$shared_bin/flow-shell-lib.sh" \
  "$shared_bin/flow-config-lib.sh" \
  "$shared_bin/agent-project-worker-status" \
  "$bin_dir/gh"

cat >"$runs_root/fl-pr-303/run.env" <<'EOF'
PR_NUMBER=303
WORKTREE=/tmp/nonexistent-worktree
PR_HEAD_REF=agent/example/pr-303
FLOW_TOOLS_DIR=/tmp/nonexistent-tools
STARTED_AT=2026-04-02T01:40:00Z
EOF

out="$(
  PATH="$bin_dir:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  ACP_EXPECTED_RUN_STARTED_AT="2026-04-02T01:39:00Z" \
  bash "$shared_bin/agent-project-reconcile-pr-session" \
    --session fl-pr-303 \
    --repo-slug example/repo \
    --repo-root "$tmpdir/repo-root" \
    --runs-root "$runs_root" \
    --history-root "$history_root"
)"

grep -q '^STATUS=STALE-RUN-SKIPPED$' <<<"$out"
grep -q '^EXPECTED_STARTED_AT=2026-04-02T01:39:00Z$' <<<"$out"
grep -q '^ACTUAL_STARTED_AT=2026-04-02T01:40:00Z$' <<<"$out"
test ! -f "$runs_root/fl-pr-303/reconciled.ok"

echo "agent-project reconcile PR session stale started_at guard test passed"
