#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SESSION_SRC="${FLOW_ROOT}/tools/bin/agent-project-run-codex-session"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

tools_dir="$tmpdir/tools"
bin_dir="$tmpdir/bin"
real_worktree="$tmpdir/worktree-real"
alias_worktree="$tmpdir/worktree-alias"
runs_root="$tmpdir/runs"
prompt_file="$tmpdir/prompt.md"
session="fl-codex-realpath-test"
run_dir="$runs_root/$session"

mkdir -p "$tools_dir" "$bin_dir" "$real_worktree" "$runs_root"
cp "$SESSION_SRC" "$tools_dir/agent-project-run-codex-session"
ln -s "$real_worktree" "$alias_worktree"

git -C "$real_worktree" init -b test >/dev/null 2>&1
printf 'Prompt body\n' >"$prompt_file"

real_worktree_path="$(cd "$real_worktree" && pwd -P)"
expected_sandbox_run_dir="${real_worktree_path}/.openclaw-artifacts/${session}"

cat >"$tools_dir/agent-project-run-codex-resilient" <<EOF
#!/usr/bin/env bash
set -euo pipefail

worktree=""
sandbox_run_dir=""

while [[ \$# -gt 0 ]]; do
  case "\$1" in
    --worktree) worktree="\${2:-}"; shift 2 ;;
    --sandbox-run-dir) sandbox_run_dir="\${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done

test "\$worktree" = "$real_worktree_path"
test "\$sandbox_run_dir" = "$expected_sandbox_run_dir"

mkdir -p "\$sandbox_run_dir"
cat >"\${sandbox_run_dir}/result.env" <<'RESULT'
OUTCOME=reported
ACTION=host-comment-scheduled-report
ISSUE_ID=321
RESULT
printf 'realpath comment\n' >"\${sandbox_run_dir}/issue-comment.md"
EOF

cat >"$bin_dir/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF

chmod +x "$tools_dir/agent-project-run-codex-session" "$tools_dir/agent-project-run-codex-resilient" "$bin_dir/codex"
PATH="$bin_dir:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
bash "$tools_dir/agent-project-run-codex-session" \
  --mode safe \
  --session "$session" \
  --worktree "$alias_worktree" \
  --prompt-file "$prompt_file" \
  --runs-root "$runs_root" \
  --adapter-id alpha \
  --task-kind issue \
  --task-id 321 \
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
grep -q '^OUTCOME=reported$' "$run_dir/result.env"
grep -q '^ACTION=host-comment-scheduled-report$' "$run_dir/result.env"
grep -q '^realpath comment$' "$run_dir/issue-comment.md"
grep -q "^WORKTREE=$alias_worktree$" "$run_dir/run.env"
grep -q "^WORKTREE_REALPATH=$real_worktree_path$" "$run_dir/run.env"

echo "agent-project codex session wrapper uses realpath for sandbox artifacts test passed"
