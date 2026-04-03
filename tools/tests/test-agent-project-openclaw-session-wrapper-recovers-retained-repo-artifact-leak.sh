#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SESSION_SRC="${FLOW_ROOT}/tools/bin/agent-project-run-openclaw-session"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

tools_dir="$tmpdir/tools"
bin_dir="$tmpdir/bin"
worktree="$tmpdir/runtime-worktrees/pr-18-20260403-104156"
runs_root="$tmpdir/runs"
retained_repo_root="$tmpdir/source-repo"
prompt_file="$tmpdir/prompt.md"
session="fl-pr-openclaw-retained-leak"
run_dir="$runs_root/$session"

mkdir -p "$tools_dir" "$bin_dir" "$worktree" "$runs_root" "$retained_repo_root"
cp "$SESSION_SRC" "$tools_dir/agent-project-run-openclaw-session"

cat >"$bin_dir/openclaw" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cmd="${1:-}"
sub="${2:-}"
case "$cmd:$sub" in
  agents:add)
    printf '{"agentId":"stub"}\n'
    ;;
  agent:*)
    leak_dir="${ACP_RETAINED_REPO_ROOT}/worktrees/$(basename "$PWD")/.openclaw-artifacts/${AGENT_PROJECT_SESSION}"
    mkdir -p "$leak_dir"
    cat >"${leak_dir}/pr-comment.md" <<'COMMENT'
# leaked summary
COMMENT
    cat >"${leak_dir}/result.env" <<'RESULT'
OUTCOME=no-change-needed
ACTION=host-refresh-pr-state
RESULT
    ;;
  *)
    echo "unexpected openclaw args: $*" >&2
    exit 64
    ;;
esac
EOF

chmod +x "$tools_dir/agent-project-run-openclaw-session" "$bin_dir/openclaw"

git -C "$worktree" init -b test >/dev/null 2>&1
git -C "$worktree" config user.name "OpenClaw"
git -C "$worktree" config user.email "openclaw@example.com"
printf 'seed\n' >"$worktree/README.md"
git -C "$worktree" add README.md
git -C "$worktree" commit -m "init" >/dev/null 2>&1
printf 'Prompt body\n' >"$prompt_file"

PATH="$bin_dir:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
ACP_RETAINED_REPO_ROOT="$retained_repo_root" \
bash "$tools_dir/agent-project-run-openclaw-session" \
  --mode safe \
  --session "$session" \
  --worktree "$worktree" \
  --prompt-file "$prompt_file" \
  --runs-root "$runs_root" \
  --adapter-id alpha \
  --task-kind pr \
  --task-id 123 \
  --openclaw-model mock/model \
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

grep -q '^OUTCOME=no-change-needed$' "$run_dir/result.env"
grep -q '^ACTION=host-refresh-pr-state$' "$run_dir/result.env"
grep -q '^# leaked summary$' "$run_dir/pr-comment.md"
test ! -e "$retained_repo_root/worktrees/$(basename "$worktree")/.openclaw-artifacts/$session"
test ! -e "$retained_repo_root/worktrees"

echo "agent-project openclaw session wrapper recovers retained repo artifact leak test passed"
