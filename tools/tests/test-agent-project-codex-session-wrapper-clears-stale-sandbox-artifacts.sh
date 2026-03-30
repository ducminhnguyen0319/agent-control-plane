#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SESSION_SRC="${FLOW_ROOT}/tools/bin/agent-project-run-codex-session"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

tools_dir="$tmpdir/tools"
bin_dir="$tmpdir/bin"
worktree="$tmpdir/worktree"
runs_root="$tmpdir/runs"
prompt_file="$tmpdir/prompt.md"
session="fl-codex-stale-sandbox"
run_dir="$runs_root/$session"
sandbox_run_dir="$worktree/.openclaw-artifacts/$session"

mkdir -p "$tools_dir" "$bin_dir" "$worktree" "$runs_root" "$sandbox_run_dir"
cp "$SESSION_SRC" "$tools_dir/agent-project-run-codex-session"

printf 'stale-result\n' >"$sandbox_run_dir/result.env"
printf '{"timestamp":"old","status":"pass","command":"stale verification"}\n' >"$sandbox_run_dir/verification.jsonl"
printf 'stale blocker\n' >"$sandbox_run_dir/issue-comment.md"

cat >"$tools_dir/agent-project-run-codex-resilient" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

sandbox_run_dir=""
output_file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sandbox-run-dir) sandbox_run_dir="${2:-}"; shift 2 ;;
    --output-file) output_file="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done

mkdir -p "$sandbox_run_dir"
cat >"${sandbox_run_dir}/result.env" <<'RESULT'
OUTCOME=implemented
ACTION=host-publish-issue-pr
RESULT
printf '{"timestamp":"new","status":"pass","command":"fresh verification"}\n' >"${sandbox_run_dir}/verification.jsonl"
printf 'mock runner wrote artifacts\n' >>"$output_file"
exit 0
EOF

cat >"$bin_dir/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF

chmod +x "$tools_dir/agent-project-run-codex-session" "$tools_dir/agent-project-run-codex-resilient" "$bin_dir/codex"

git -C "$worktree" init -b test >/dev/null 2>&1
printf 'Prompt body\n' >"$prompt_file"

bash "$tools_dir/agent-project-run-codex-session" \
  --mode safe \
  --session "$session" \
  --worktree "$worktree" \
  --prompt-file "$prompt_file" \
  --runs-root "$runs_root" \
  --adapter-id alpha \
  --task-kind issue \
  --task-id 123 \
  --safe-profile mock-safe \
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
  echo "stale verification entry leaked into codex cycle" >&2
  exit 1
fi
if [[ -e "$run_dir/issue-comment.md" ]]; then
  echo "stale codex issue comment leaked into host run dir" >&2
  exit 1
fi
if [[ -e "$sandbox_run_dir/issue-comment.md" ]]; then
  echo "stale codex sandbox comment artifact was not cleared" >&2
  exit 1
fi

echo "agent-project codex session wrapper clears stale sandbox artifacts test passed"
