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
EOF

cat >"$templates_dir/scheduled-issue-prompt-template.md" <<'EOF'
Scheduled issue {ISSUE_ID}: {ISSUE_TITLE}
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
if [[ "${1:-}" == "api" && "${2:-}" == "rate_limit" ]]; then
  printf '5000\n'
  exit 0
fi
if [[ "${1:-}" == "issue" && "${2:-}" == "view" ]]; then
  issue_id="${3:-0}"
  cat <<JSON
{"number":${issue_id},"title":"Stub issue ${issue_id}","body":${GH_STUB_ISSUE_BODY_JSON:?},"url":"https://example.test/issues/${issue_id}","labels":[],"comments":[]}
JSON
  exit 0
fi
if [[ "${1:-}" == "issue" && "${2:-}" == "comment" ]]; then
  exit 0
fi
exit 64
EOF
chmod +x "$shim_dir/gh"

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
printf '%s\n' "${F_LOSNING_WORKTREE_LOCAL_INSTALL:-false}" >"$capture_dir/local-install-${issue_id}.txt"
if [[ "${ACP_WORKTREE_LOCAL_INSTALL:-}" == "true" ]]; then
  printf '%s\n' "${ACP_WORKTREE_LOCAL_INSTALL}" >"$capture_dir/local-install-${issue_id}.txt"
fi
printf 'WORKTREE=%s\n' "$worktree"
printf 'BRANCH=agent/alpha/issue-%s-test\n' "$issue_id"
EOF
chmod +x "$bin_dir/new-worktree.sh"

cat >"$bin_dir/reuse-issue-worktree.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
worktree="${1:?worktree required}"
issue_id="${2:?issue id required}"
capture_dir="${TEST_CAPTURE_DIR:?}"
printf '%s\n' "${F_LOSNING_WORKTREE_LOCAL_INSTALL:-false}" >"$capture_dir/local-install-${issue_id}.txt"
if [[ "${ACP_WORKTREE_LOCAL_INSTALL:-}" == "true" ]]; then
  printf '%s\n' "${ACP_WORKTREE_LOCAL_INSTALL}" >"$capture_dir/local-install-${issue_id}.txt"
fi
printf 'WORKTREE=%s\n' "$worktree"
printf 'BRANCH=agent/alpha/issue-%s-reused\n' "$issue_id"
printf 'BASE_REF=origin/main\n'
printf 'REUSED=yes\n'
EOF
chmod +x "$bin_dir/reuse-issue-worktree.sh"

cat >"$bin_dir/run-codex-safe.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$bin_dir/run-codex-safe.sh"

run_case() {
  local issue_id="${1:?issue id required}"
  local expected="${2:?expected flag required}"
  local issue_body="${3:?issue body required}"
  local capture_dir="$tmpdir/case-${issue_id}"
  mkdir -p "$capture_dir"

  GH_STUB_ISSUE_BODY_JSON="$(printf '%s' "$issue_body" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" \
  TEST_CAPTURE_DIR="$capture_dir" \
  ACP_ROOT="$FLOW_ROOT" \
  ACP_PROJECT_ID="alpha" \
  ACP_AGENT_ROOT="$agent_root" \
  ACP_RESIDENT_ISSUE_WORKERS_ENABLED=0 \
  PATH="$shim_dir:$PATH" \
  bash "$bin_dir/start-issue-worker.sh" "$issue_id" >/dev/null

  actual="$(cat "$capture_dir/local-install-${issue_id}.txt")"
  [[ "$actual" == "$expected" ]]
}

scheduled_verify_body="$(cat <<'EOF'
## Summary
Recurring verification.

Schedule: every 1h

## Commands
1. `pnpm run verify:web:main`
EOF
)"

scheduled_install_body="$(cat <<'EOF'
## Summary
Recurring dependency refresh.

Schedule: every 1h

## Commands
1. `pnpm install --frozen-lockfile`
2. `pnpm run verify:web:main`
EOF
)"

run_case 440 false "$scheduled_verify_body"
run_case 441 true "$scheduled_install_body"

echo "start issue worker local-install routing test passed"
