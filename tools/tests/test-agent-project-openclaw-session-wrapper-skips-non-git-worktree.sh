#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SESSION_SRC="${FLOW_ROOT}/tools/bin/agent-project-run-openclaw-session"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

tools_dir="$tmpdir/tools"
bin_dir="$tmpdir/bin"
worktree="$tmpdir/worktree"
runs_root="$tmpdir/runs"
prompt_file="$tmpdir/prompt.md"
session="fl-openclaw-non-git-worktree"
run_dir="$runs_root/$session"

mkdir -p "$tools_dir" "$bin_dir" "$worktree" "$runs_root"
cp "$SESSION_SRC" "$tools_dir/agent-project-run-openclaw-session"

cat >"$bin_dir/openclaw" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cmd="${1:-}"
sub="${2:-}"
case "$cmd:$sub" in
  agents:list)
    printf '[]
'
    ;;
  agents:add)
    shift 2
    agent_dir=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --agent-dir) agent_dir="${2:-}"; shift 2 ;;
        --workspace|--model) shift 2 ;;
        --non-interactive|--json) shift ;;
        *) shift ;;
      esac
    done
    mkdir -p "${agent_dir:-/tmp/ignored}"
    printf '{"agentId":"stub"}
'
    ;;
  agent:--agent)
    mkdir -p "${ACP_RUN_DIR:?}"
    cat >"${ACP_RESULT_FILE:?}" <<'RESULT'
OUTCOME=reported
ACTION=host-comment-scheduled-report
RESULT
    printf 'non-git report
' >"${ACP_RUN_DIR}/issue-comment.md"
    printf '{"payloads":[{"text":"DONE"}]}
'
    ;;
  agents:delete)
    printf '{"deleted":true}
'
    ;;
  *)
    echo "unexpected openclaw args: $*" >&2
    exit 64
    ;;
esac
EOF

chmod +x "$tools_dir/agent-project-run-openclaw-session" "$bin_dir/openclaw"
printf 'Prompt body
' >"$prompt_file"

PATH="$bin_dir:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" bash "$tools_dir/agent-project-run-openclaw-session"   --mode safe   --session "$session"   --worktree "$worktree"   --prompt-file "$prompt_file"   --runs-root "$runs_root"   --adapter-id alpha   --task-kind issue   --task-id 123   --openclaw-model mock/model   --collect-file issue-comment.md   >/dev/null

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
grep -q '^non-git report$' "$run_dir/issue-comment.md"
grep -q '^FINAL_HEAD=' "$run_dir/run.env"
grep -q '^FINAL_BRANCH=' "$run_dir/run.env"

echo "agent-project openclaw session wrapper supports non-git worktree test passed"
