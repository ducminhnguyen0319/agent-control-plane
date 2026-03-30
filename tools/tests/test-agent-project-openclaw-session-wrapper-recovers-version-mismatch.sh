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
session="resident-version-reset"
run_dir="$runs_root/$session"
operation_log="$tmpdir/openclaw.log"
attempt_file="$tmpdir/attempts"
resident_agent_dir="$tmpdir/resident/openclaw-agent"

mkdir -p "$tools_dir" "$bin_dir" "$worktree" "$runs_root"
cp "$SESSION_SRC" "$tools_dir/agent-project-run-openclaw-session"

cat >"$bin_dir/openclaw" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

op_log="${ACP_TEST_OP_LOG:?}"
attempt_file="${ACP_TEST_ATTEMPT_FILE:?}"
cmd="${1:-}"
sub="${2:-}"

case "$cmd:$sub" in
  agents:list)
    shift 2 || true
    printf 'agents:list\n' >>"$op_log"
    if [[ -f "${ACP_RESIDENT_OPENCLAW_AGENT_DIR}/created" ]]; then
      printf '{"agents":[{"id":"resident-agent"}]}\n'
    else
      printf '{"agents":[]}\n'
    fi
    ;;
  agents:add)
    shift 2 || true
    agent_id="${1:-}"
    printf 'agents:add:%s\n' "$agent_id" >>"$op_log"
    mkdir -p "${ACP_RESIDENT_OPENCLAW_AGENT_DIR}"
    : >"${ACP_RESIDENT_OPENCLAW_AGENT_DIR}/created"
    printf '{"agentId":"%s"}\n' "$agent_id"
    ;;
  agents:delete)
    shift 2 || true
    printf 'agents:delete\n' >>"$op_log"
    rm -f "${ACP_RESIDENT_OPENCLAW_AGENT_DIR}/created"
    printf '{"deleted":true}\n'
    ;;
  agent:*)
    current_attempt=0
    if [[ -f "$attempt_file" ]]; then
      current_attempt="$(cat "$attempt_file")"
    fi
    current_attempt=$((current_attempt + 1))
    printf '%s\n' "$current_attempt" >"$attempt_file"
    printf 'agent:run:%s\n' "$current_attempt" >>"$op_log"
    if [[ "$current_attempt" == "1" ]]; then
      printf 'Config was last written by a newer OpenClaw (2026.3.23-2); current version is 2026.3.12.\n' >&2
      exit 1
    fi
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
  --openclaw-agent-dir "$resident_agent_dir" \
  --openclaw-state-dir "$tmpdir/resident/openclaw-state" \
  --openclaw-config-path "$tmpdir/resident/openclaw-config/openclaw.json" \
  --openclaw-model mock/model \
  --context "TEST_OP_LOG=$operation_log" \
  --context "TEST_ATTEMPT_FILE=$attempt_file" \
  --context "RESIDENT_OPENCLAW_AGENT_DIR=$resident_agent_dir" \
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
grep -q '^agents:add:resident-agent$' "$operation_log"
[[ "$(grep -c '^agents:add:resident-agent$' "$operation_log" || true)" == "2" ]]
[[ "$(grep -c '^agent:run:' "$operation_log" || true)" == "2" ]]

echo "agent-project openclaw session wrapper recovers version mismatch test passed"
