#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SESSION_SRC="${FLOW_ROOT}/tools/bin/agent-project-run-openclaw-session"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

tools_dir="$tmpdir/tools"
bin_dir="$tmpdir/bin"
worktree_one="$tmpdir/worktree-one"
worktree_two="$tmpdir/worktree-two"
runs_root="$tmpdir/runs"
prompt_file="$tmpdir/prompt.md"
session="resident-issue-openclaw"
run_dir="$runs_root/$session"
operation_log="$tmpdir/openclaw.log"
state_file="$tmpdir/agent-present"
config_path="$tmpdir/resident/openclaw-config/openclaw.json"

mkdir -p "$tools_dir" "$bin_dir" "$worktree_one" "$worktree_two" "$runs_root"
cp "$SESSION_SRC" "$tools_dir/agent-project-run-openclaw-session"

cat >"$bin_dir/openclaw" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

op_log="${ACP_TEST_OP_LOG:?}"
state_file="${ACP_TEST_STATE_FILE:?}"
cmd="${1:-}"
sub="${2:-}"

case "$cmd:$sub" in
  agents:list)
    shift 2 || true
    printf 'agents:list\n' >>"$op_log"
    if [[ -f "$state_file" ]]; then
      printf '{"agents":[{"id":"resident-agent"}]}\n'
    else
      printf '{"agents":[]}\n'
    fi
    ;;
  agents:add)
    shift 2 || true
    agent_id="${1:-}"
    printf 'agents:add:%s\n' "$agent_id" >>"$op_log"
    : >"$state_file"
    mkdir -p .openclaw
    printf 'state\n' >.openclaw/workspace-state.json
    : >SOUL.md
    : >TOOLS.md
    : >IDENTITY.md
    : >USER.md
    : >HEARTBEAT.md
    : >BOOTSTRAP.md
    printf '{"agentId":"%s"}\n' "$agent_id"
    ;;
  agents:delete)
    shift 2 || true
    agent_id="${1:-}"
    printf 'agents:delete:%s\n' "$agent_id" >>"$op_log"
    rm -f "$state_file"
    printf '{"deleted":true}\n'
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
    printf 'artifact-from-openclaw\n' >"${ACP_RUN_DIR}/mock.txt"
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

for worktree in "$worktree_one" "$worktree_two"; do
  git -C "$worktree" init -b test >/dev/null 2>&1
  git -C "$worktree" config user.name "OpenClaw"
  git -C "$worktree" config user.email "openclaw@example.com"
  printf 'seed\n' >"$worktree/README.md"
  git -C "$worktree" add README.md
  git -C "$worktree" commit -m "init" >/dev/null 2>&1
done
printf 'Prompt body\n' >"$prompt_file"

run_wrapper() {
  local worktree="${1:?worktree required}"
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
    --openclaw-config-path "$config_path" \
    --openclaw-model mock/model \
    --context "TEST_OP_LOG=$operation_log" \
    --context "TEST_STATE_FILE=$state_file" \
    --collect-file mock.txt \
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
}

run_wrapper "$worktree_one"
run_wrapper "$worktree_two"

test -f "$run_dir/result.env"
test -f "$run_dir/mock.txt"
grep -q '^OUTCOME=implemented$' "$run_dir/result.env"
grep -q '^ACTION=host-publish-issue-pr$' "$run_dir/result.env"
grep -q '^OPENCLAW_KEEP_AGENT=true$' "$run_dir/run.env"
test -f "$config_path"
python3 - "$config_path" "$worktree_two" "$tmpdir/resident/openclaw-agent" <<'PY'
import json
import sys

config_path, expected_workspace, expected_agent_dir = sys.argv[1:4]
with open(config_path, "r", encoding="utf-8") as handle:
    payload = json.load(handle)
agents = payload.get("agents", {}).get("list", [])
resident = next((agent for agent in agents if agent.get("id") == "resident-agent"), None)
if resident is None:
    raise SystemExit(1)
if resident.get("workspace") != expected_workspace:
    raise SystemExit(1)
if resident.get("agentDir") != expected_agent_dir:
    raise SystemExit(1)
if resident.get("model") != "mock/model":
    raise SystemExit(1)
PY

add_count="$(grep -c '^agents:add:resident-agent$' "$operation_log" || true)"
run_count="$(grep -c '^agent:run:resident-agent:resident-session$' "$operation_log" || true)"
delete_count="$(grep -c '^agents:delete:resident-agent$' "$operation_log" || true)"

[[ "$add_count" == "1" ]]
[[ "$run_count" == "2" ]]
[[ "$delete_count" == "0" ]]

echo "agent-project openclaw resident session wrapper test passed"
