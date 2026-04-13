#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SESSION_SRC="${FLOW_ROOT}/tools/bin/agent-project-run-codex-session"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/codex-var-tmp-recovery.XXXXXX")"
fallback_dir="$(mktemp -d /var/tmp/acp-codex-fallback.XXXXXX)"
trap 'rm -rf "$tmpdir" "$fallback_dir"' EXIT

tools_dir="$tmpdir/tools"
bin_dir="$tmpdir/bin"
worktree="$tmpdir/worktree"
runs_root="$tmpdir/runs"
prompt_file="$tmpdir/prompt.md"
session="fl-codex-var-tmp-recovery"
run_dir="$runs_root/$session"

mkdir -p "$tools_dir" "$bin_dir" "$worktree" "$runs_root"
cp "$SESSION_SRC" "$tools_dir/agent-project-run-codex-session"

cat >"$tools_dir/agent-project-run-codex-resilient" <<EOF
#!/usr/bin/env bash
set -euo pipefail

output_file=""

while [[ \$# -gt 0 ]]; do
  case "\$1" in
    --output-file) output_file="\${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done

cat >"$fallback_dir/issue-comment.md" <<'COMMENT'
recovered from /var/tmp fallback
COMMENT
cat >"$fallback_dir/result.env" <<'RESULT'
OUTCOME=blocked
ACTION=host-comment-blocker
ISSUE_ID=654
RESULT

{
  printf 'comment=%s\n' "$fallback_dir/issue-comment.md"
  printf 'result=%s\n' "$fallback_dir/result.env"
} >>"\$output_file"
EOF

cat >"$bin_dir/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF

chmod +x "$tools_dir/agent-project-run-codex-session" "$tools_dir/agent-project-run-codex-resilient" "$bin_dir/codex"

git -C "$worktree" init -b test >/dev/null 2>&1
printf 'Prompt body\n' >"$prompt_file"

PATH="$bin_dir:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin" \
bash "$tools_dir/agent-project-run-codex-session" \
  --mode safe \
  --session "$session" \
  --worktree "$worktree" \
  --prompt-file "$prompt_file" \
  --runs-root "$runs_root" \
  --adapter-id alpha \
  --task-kind issue \
  --task-id 654 \
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
test -f "$run_dir/issue-comment.md"
grep -q '^OUTCOME=blocked$' "$run_dir/result.env"
grep -q '^ACTION=host-comment-blocker$' "$run_dir/result.env"
grep -q '^recovered from /var/tmp fallback$' "$run_dir/issue-comment.md"

echo "agent-project codex session wrapper recovers var tmp logged artifacts test passed"
