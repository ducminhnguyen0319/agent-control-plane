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
session="resident-add-race"
run_dir="$runs_root/$session"
operation_log="$tmpdir/openclaw.log"

mkdir -p "$tools_dir" "$bin_dir" "$worktree" "$runs_root"
cp "$SESSION_SRC" "$tools_dir/agent-project-run-openclaw-session"

cat >"$bin_dir/openclaw" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

op_log="${ACP_TEST_OP_LOG:?}"
cmd="${1:-}"
sub="${2:-}"

case "$cmd:$sub" in
  agents:list)
    shift 2 || true
    printf 'agents:list\n' >>"$op_log"
    printf '{"agents":[]}\n'
    ;;
  agents:add)
    shift 2 || true
    agent_id="${1:-}"
    printf 'agents:add:%s\n' "$agent_id" >>"$op_log"
    printf 'Agent "%s" already exists.\n' "$agent_id" >&2
    exit 1
    ;;
  agent:*)
    shift 1 || true
    agent_id=""
    session_id=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --agent) agent_id="${2:-}"; shift 2 ;;
        --session-id) session_id="${2:-}"; shift 2 ;;
        *) shift ;;
      esac
    done
    printf 'agent:run:%s:%s\n' "$agent_id" "$session_id" >>"$op_log"
    mkdir -p "${ACP_RUN_DIR:?}"
    cat >"${ACP_RESULT_FILE:?}" <<'RESULT'
OUTCOME=implemented
ACTION=host-publish-issue-pr
RESULT
    printf '{"status":"pass","command":"mock verification"}\n' >"${ACP_RUN_DIR}/verification.jsonl"
    printf '{"payloads":[{"text":"DONE"}]}\n'
    ;;
  *)
    echo "unexpected openclaw args: $cmd $sub $*" >&2
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
bash "$tools_dir/agent-project-run-openclaw-session" \
  --mode safe \
  --session "$session" \
  --worktree "$worktree" \
  --prompt-file "$prompt_file" \
  --runs-root "$runs_root" \
  --adapter-id alpha \
  --task-kind issue \
  --task-id 123 \
  --keep-agent \
  --openclaw-agent-id resident-agent \
  --openclaw-session-id resident-session \
  --openclaw-agent-dir "$tmpdir/resident/openclaw-agent" \
  --openclaw-state-dir "$tmpdir/resident/openclaw-state" \
  --openclaw-config-path "$tmpdir/resident/openclaw-config/openclaw.json" \
  --openclaw-model mock/model \
  --context "TEST_OP_LOG=$operation_log" \
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
grep -q '^OUTCOME=implemented$' "$run_dir/result.env"
grep -q '^ACTION=host-publish-issue-pr$' "$run_dir/result.env"
grep -q 'reusing existing agent after add race' "$run_dir/$session.log"
[[ "$(grep -c '^agents:add:resident-agent$' "$operation_log" || true)" == "1" ]]
[[ "$(grep -c '^agent:run:resident-agent:resident-session$' "$operation_log" || true)" == "1" ]]

echo "agent-project openclaw session wrapper reuses existing agent after add race test passed"
