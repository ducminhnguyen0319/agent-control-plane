#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${FLOW_ROOT}/tools/bin/agent-project-reconcile-pr-session"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

shared_home="$tmpdir/shared-home"
shared_bin="$shared_home/tools/bin"
runs_root="$tmpdir/runs"
history_root="$tmpdir/history"
repo_root="$tmpdir/repo"
bin_dir="$tmpdir/bin"
hook_file="$tmpdir/hooks.sh"
merged_file="$tmpdir/merged.txt"
retry_cleared_file="$tmpdir/retry-cleared.txt"
merge_called_file="$tmpdir/merge-called.txt"
approve_called_file="$tmpdir/approve-called.txt"
pr_state_file="$tmpdir/pr-state.txt"

mkdir -p "$shared_bin" "$runs_root/fl-pr-92" "$history_root" "$repo_root" "$bin_dir"
git -C "$repo_root" init -b main >/dev/null 2>&1
printf 'OPEN\n' >"$pr_state_file"

cat >"$runs_root/fl-pr-92/run.env" <<'EOF'
PR_NUMBER=92
SESSION=fl-pr-92
WORKTREE=/tmp/nonexistent-pr-worktree
EOF

cat >"$runs_root/fl-pr-92/result.env" <<'EOF'
OUTCOME=approved-local-review-passed
ACTION=host-approve-and-merge
EOF

cat >"$shared_bin/agent-project-worker-status" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cat <<OUT
STATUS=SUCCEEDED
META_FILE=${runs_root}/fl-pr-92/run.env
OUT
EOF

cat >"$shared_bin/agent-project-cleanup-session" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF

cat >"$hook_file" <<EOF
pr_clear_retry() {
  : >"${retry_cleared_file}"
}
pr_after_merged() {
  : >"${merged_file}"
}
pr_cleanup_merged_residue() { :; }
pr_after_reconciled() { :; }
pr_automerge_allowed() { printf 'yes\n'; }
EOF

cat >"$bin_dir/gh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" == "api" && "\${2:-}" == "user" ]]; then
  printf 'codex-bot\n'
  exit 0
fi
if [[ "\${1:-}" == "pr" && "\${2:-}" == "view" ]]; then
  if [[ " \$* " == *" --json author "* ]]; then
    printf '{"author":{"login":"codex-bot"}}\n'
    exit 0
  fi
  state="\$(cat "${pr_state_file}")"
  printf '{"state":"%s","baseRefName":"main","comments":[]}\n' "\$state"
  exit 0
fi
if [[ "\${1:-}" == "pr" && "\${2:-}" == "merge" ]]; then
  : >"${merge_called_file}"
  printf 'MERGED\n' >"${pr_state_file}"
  exit 0
fi
if [[ "\${1:-}" == "api" && " \$* " == *" /pulls/92/reviews "* ]]; then
  : >"${approve_called_file}"
  printf '{}\n'
  exit 0
fi
exit 0
EOF

chmod +x \
  "$shared_bin/agent-project-worker-status" \
  "$shared_bin/agent-project-cleanup-session" \
  "$bin_dir/gh"

output="$(
  PATH="$bin_dir:$PATH" \
  SHARED_AGENT_HOME="$shared_home" \
  bash "$SCRIPT" \
    --session fl-pr-92 \
    --repo-slug example/repo \
    --repo-root "$repo_root" \
    --runs-root "$runs_root" \
    --history-root "$history_root" \
    --hook-file "$hook_file"
)"

test -f "$retry_cleared_file"
test -f "$merged_file"
test -f "$merge_called_file"
test ! -f "$approve_called_file"
grep -q '^STATUS=SUCCEEDED$' <<<"$output"
grep -q '^OUTCOME=merged$' <<<"$output"
grep -q '^ACTION=approved-and-merged$' <<<"$output"

echo "pr reconcile skips self approval test passed"
