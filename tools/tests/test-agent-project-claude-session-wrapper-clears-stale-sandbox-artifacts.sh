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
session="acp-claude-stale-sandbox"
run_dir="$runs_root/$session"
sandbox_run_dir="$worktree/.openclaw-artifacts/$session"

mkdir -p "$tools_dir" "$bin_dir" "$worktree" "$runs_root" "$sandbox_run_dir"
cp "$SESSION_SRC" "$tools_dir/agent-project-run-claude-session"

printf 'stale-result\n' >"$sandbox_run_dir/result.env"
printf '{"timestamp":"old","status":"pass","command":"stale verification"}\n' >"$sandbox_run_dir/verification.jsonl"
printf 'stale blocker\n' >"$sandbox_run_dir/issue-comment.md"

cat >"$bin_dir/claude" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cat >"${ACP_RESULT_FILE:?}" <<'RESULT'
OUTCOME=implemented
ACTION=host-publish-issue-pr
RESULT
printf '{"timestamp":"new","status":"pass","command":"fresh verification"}\n' >"${ACP_RUN_DIR:?}/verification.jsonl"
printf 'mock claude finished\n'
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
  --claude-effort high \
  --collect-file verification.jsonl \
  --collect-file issue-comment.md \
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
test -f "$run_dir/verification.jsonl"
grep -q '^OUTCOME=implemented$' "$run_dir/result.env"
grep -q 'fresh verification' "$run_dir/verification.jsonl"
if grep -q 'stale verification' "$run_dir/verification.jsonl"; then
  echo "stale verification entry leaked into claude cycle" >&2
  exit 1
fi
if [[ -e "$run_dir/issue-comment.md" ]]; then
  echo "stale claude issue comment leaked into host run dir" >&2
  exit 1
fi
if [[ -e "$sandbox_run_dir/issue-comment.md" ]]; then
  echo "stale claude sandbox comment artifact was not cleared" >&2
  exit 1
fi

echo "agent-project claude session wrapper clears stale sandbox artifacts test passed"
