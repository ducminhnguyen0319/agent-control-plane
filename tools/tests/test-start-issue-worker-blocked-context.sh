#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REAL_WORKER="${FLOW_ROOT}/tools/bin/start-issue-worker.sh"
REAL_POLICY_BIN="${FLOW_ROOT}/tools/bin/issue-requires-local-workspace-install.sh"
REAL_CONFIG_LIB="${FLOW_ROOT}/tools/bin/flow-config-lib.sh"
REAL_SHELL_LIB="${FLOW_ROOT}/tools/bin/flow-shell-lib.sh"
REAL_RESIDENT_LIB="${FLOW_ROOT}/tools/bin/flow-resident-worker-lib.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

workspace="$tmpdir/workspace"
bin_dir="$workspace/bin"
templates_dir="$workspace/templates"
shim_dir="$tmpdir/shim"
agent_root="$tmpdir/agent"

mkdir -p "$bin_dir" "$templates_dir" "$shim_dir" "$agent_root"
ln -s "$REAL_WORKER" "$bin_dir/start-issue-worker.sh"
ln -s "$REAL_POLICY_BIN" "$bin_dir/issue-requires-local-workspace-install.sh"
ln -s "$REAL_CONFIG_LIB" "$bin_dir/flow-config-lib.sh"
ln -s "$REAL_SHELL_LIB" "$bin_dir/flow-shell-lib.sh"
ln -s "$REAL_RESIDENT_LIB" "$bin_dir/flow-resident-worker-lib.sh"

cat >"$templates_dir/issue-prompt-template.md" <<'EOF'
Issue {ISSUE_ID}: {ISSUE_TITLE}
{ISSUE_BLOCKER_CONTEXT}
EOF

cat >"$templates_dir/scheduled-issue-prompt-template.md" <<'EOF'
Scheduled issue {ISSUE_ID}: {ISSUE_TITLE}
{ISSUE_BLOCKER_CONTEXT}
EOF

cat >"$shim_dir/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "has-session" ]]; then
  exit 1
fi
exit 0
EOF
chmod +x "$shim_dir/tmux"

cat >"$shim_dir/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "issue" && "${2:-}" == "view" ]]; then
  issue_id="${3:-0}"
  cat <<JSON
{"number":${issue_id},"title":"Blocked issue ${issue_id}","body":"Investigate blocked issue.","url":"https://example.test/issues/${issue_id}","labels":[{"name":"agent-blocked"}],"comments":[{"body":"Host-side publish blocked for session \`fl-issue-${issue_id}\`.\n\n\`\`\`text\nScope guard blocked issue #${issue_id} from publishing as a single PR.\n\`\`\`","createdAt":"2026-03-15T10:00:00Z"}]}
JSON
  exit 0
fi
if [[ "${1:-}" == "issue" && "${2:-}" == "comment" ]]; then
  exit 0
fi
exit 64
EOF
chmod +x "$shim_dir/gh"

cat >"$bin_dir/retry-state.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat <<'OUT'
KIND=issue
ITEM_ID=555
ATTEMPTS=3
NEXT_ATTEMPT_EPOCH=0
NEXT_ATTEMPT_AT=2026-03-15T11:00:00Z
LAST_REASON=scope-guard-blocked
UPDATED_AT=2026-03-15T10:55:00Z
OUT
EOF
chmod +x "$bin_dir/retry-state.sh"

cat >"$bin_dir/new-worktree.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
issue_id="${1:?issue id required}"
capture_dir="${TEST_CAPTURE_DIR:?}"
mkdir -p "$capture_dir"
worktree="$capture_dir/worktree-${issue_id}"
mkdir -p "$worktree"
if [[ ! -d "$worktree/.git" ]]; then
  git -C "$worktree" init -b main >/dev/null 2>&1
  git -C "$worktree" config user.name "Codex"
  git -C "$worktree" config user.email "codex@example.com"
  printf 'stub\n' >"$worktree/README.md"
  git -C "$worktree" add README.md
  git -C "$worktree" commit -m "init" >/dev/null 2>&1
fi
printf 'WORKTREE=%s\n' "$worktree"
printf 'BRANCH=agent/alpha/issue-%s-test\n' "$issue_id"
EOF
chmod +x "$bin_dir/new-worktree.sh"

cat >"$bin_dir/run-codex-safe.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$bin_dir/run-codex-safe.sh"

capture_dir="$tmpdir/case-blocked"
mkdir -p "$capture_dir"

TEST_CAPTURE_DIR="$capture_dir" \
ACP_ROOT="$FLOW_ROOT" \
ACP_PROJECT_ID="alpha" \
ACP_AGENT_ROOT="$agent_root" \
ACP_RUNS_ROOT="$agent_root/runs" \
ACP_HISTORY_ROOT="$agent_root/history" \
PATH="$shim_dir:$PATH" \
bash "$bin_dir/start-issue-worker.sh" 555 >/dev/null

prompt_file="$(find "$agent_root/runs" -maxdepth 2 -name prompt.md | head -n 1)"
test -n "$prompt_file"

grep -q '## Prior Blocker Context' "$prompt_file"
grep -q 'This issue is being retried after an `agent-blocked` stop.' "$prompt_file"
grep -q 'Scope guard blocked issue #555 from publishing as a single PR.' "$prompt_file"
grep -q 'Last recorded blocker: `scope-guard-blocked`.' "$prompt_file"
grep -q 'Blocked retries so far: 3.' "$prompt_file"
grep -q 'create-follow-up-issue.sh' "$prompt_file"

echo "start issue worker blocked-context test passed"
