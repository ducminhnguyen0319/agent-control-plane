#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SESSION_SRC="${FLOW_ROOT}/tools/bin/agent-project-run-claude-session"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

tools_dir="$tmpdir/tools"
bin_dir="$tmpdir/bin"
worktree="$tmpdir/worktree"
runs_root="$tmpdir/runs"
prompt_file="$tmpdir/prompt.md"
session="acp-issue-claude-timeout"
run_dir="$runs_root/$session"

mkdir -p "$tools_dir" "$bin_dir" "$worktree" "$runs_root"
cp "$SESSION_SRC" "$tools_dir/agent-project-run-claude-session"

cat >"$bin_dir/claude" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

sleep 2
printf 'finished too late\n'
EOF

chmod +x "$tools_dir/agent-project-run-claude-session" "$bin_dir/claude"

git -C "$worktree" init -b test >/dev/null 2>&1
printf 'Prompt body\n' >"$prompt_file"

PATH="$bin_dir:$PATH" \
bash "$tools_dir/agent-project-run-claude-session" \
  --mode safe \
  --session "$session" \
  --worktree "$worktree" \
  --prompt-file "$prompt_file" \
  --runs-root "$runs_root" \
  --adapter-id alpha \
  --task-kind issue \
  --task-id 123 \
  --claude-model sonnet \
  --claude-permission-mode dontAsk \
  --claude-effort medium \
  --claude-timeout-seconds 1 \
  --claude-max-attempts 1 \
  --claude-retry-backoff-seconds 0 \
  >/dev/null

for _ in $(seq 1 50); do
  if ! tmux has-session -t "$session" 2>/dev/null; then
    break
  fi
  sleep 0.2
done

if tmux has-session -t "$session" 2>/dev/null; then
  echo "tmux session did not exit" >&2
  exit 1
fi

test -f "$run_dir/result.env"
grep -q '^OUTCOME=blocked$' "$run_dir/result.env"
grep -q '^ACTION=host-comment-blocker$' "$run_dir/result.env"
grep -q '^DETAIL=worker-exit-124$' "$run_dir/result.env"
grep -q '^RUNNER_STATE=failed$' "$run_dir/runner.env"
grep -q '^LAST_EXIT_CODE=124$' "$run_dir/runner.env"
grep -q '^LAST_FAILURE_REASON=timeout$' "$run_dir/runner.env"
grep -q '__CLAUDE_EXIT__:124' "$run_dir/$session.log"

echo "agent-project claude timeout wrapper test passed"
