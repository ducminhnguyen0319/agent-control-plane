#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_SCRIPT="${FLOW_ROOT}/tools/bin/heartbeat-safe-auto.sh"
FLOW_CONFIG_LIB="${FLOW_ROOT}/tools/bin/flow-config-lib.sh"
FLOW_LIB="${FLOW_ROOT}/tools/bin/flow-shell-lib.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

shared_home="$tmpdir/shared-home"
flow_root="$shared_home/skills/openclaw/agent-control-plane"
bin_dir="$tmpdir/bin"
agent_root="$tmpdir/project"
memory_dir="$tmpdir/memory"
log_file="$tmpdir/heartbeat.log"
profile_home="$tmpdir/profiles"

mkdir -p \
  "$flow_root/tools/bin" \
  "$flow_root/hooks" \
  "$shared_home/skills/openclaw/codex-quota-manager/scripts" \
  "$bin_dir" \
  "$agent_root/runs" \
  "$agent_root/state" \
  "$memory_dir" \
  "$profile_home"

cp "$SOURCE_SCRIPT" "$flow_root/tools/bin/heartbeat-safe-auto.sh"
cp "$FLOW_CONFIG_LIB" "$flow_root/tools/bin/flow-config-lib.sh"
cp "$FLOW_LIB" "$flow_root/tools/bin/flow-shell-lib.sh"

cat >"$flow_root/tools/bin/audit-retained-worktrees.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'LEGACY_RETAINED_WORKTREE_COUNT=0\n'
printf 'LEGACY_RETAINED_WORKTREE_CLEANED=0\n'
EOF

cat >"$flow_root/tools/bin/audit-agent-worktrees.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'LEGACY_AGENT_WORKTREE_COUNT=0\n'
printf 'LEGACY_AGENT_WORKTREE_CLEANED=0\n'
EOF

cat >"$flow_root/tools/bin/agent-project-heartbeat-loop" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'heartbeat-loop-ran\n'
EOF

cat >"$flow_root/tools/bin/agent-project-catch-up-merged-prs" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'catchup-ran\n'
EOF

cat >"$flow_root/tools/bin/agent-project-catch-up-issue-pr-links" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'issue-link-catchup-ran\n'
EOF

cat >"$flow_root/hooks/heartbeat-hooks.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
EOF

cat >"$shared_home/skills/openclaw/codex-quota-manager/scripts/auto-switch.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'quota-switch-should-not-run\n'
EOF

cat >"$bin_dir/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "list-sessions" ]]; then
  exit 1
fi
if [[ "${1:-}" == "has-session" ]]; then
  exit 1
fi
exit 0
EOF

cat >"$bin_dir/ps" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF

cat >"$bin_dir/codex-quota" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'codex-quota-should-not-run\n'
exit 1
EOF

chmod +x \
  "$flow_root/tools/bin/flow-shell-lib.sh" \
  "$flow_root/tools/bin/flow-config-lib.sh" \
  "$flow_root/tools/bin/heartbeat-safe-auto.sh" \
  "$flow_root/tools/bin/audit-retained-worktrees.sh" \
  "$flow_root/tools/bin/audit-agent-worktrees.sh" \
  "$flow_root/tools/bin/agent-project-heartbeat-loop" \
  "$flow_root/tools/bin/agent-project-catch-up-merged-prs" \
  "$flow_root/tools/bin/agent-project-catch-up-issue-pr-links" \
  "$flow_root/hooks/heartbeat-hooks.sh" \
  "$shared_home/skills/openclaw/codex-quota-manager/scripts/auto-switch.sh" \
  "$bin_dir/tmux" \
  "$bin_dir/ps" \
  "$bin_dir/codex-quota"

PATH="$bin_dir:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
SHARED_AGENT_HOME="$shared_home" \
ACP_PROFILE_REGISTRY_ROOT="$profile_home" \
F_LOSNING_AGENT_ROOT="$agent_root" \
F_LOSNING_RUNS_ROOT="$agent_root/runs" \
F_LOSNING_STATE_ROOT="$agent_root/state" \
F_LOSNING_MEMORY_DIR="$memory_dir" \
F_LOSNING_HEARTBEAT_LOOP_TIMEOUT_SECONDS=10 \
F_LOSNING_CATCHUP_TIMEOUT_SECONDS=10 \
bash "$flow_root/tools/bin/heartbeat-safe-auto.sh" >"$log_file"

grep -q '^CODEX_QUOTA_ROTATION_STRATEGY=failure-driven$' "$log_file"
grep -q '^CODEX_QUOTA_PREFLIGHT_SKIPPED=strategy-failure-driven$' "$log_file"
if grep -q 'quota-switch-should-not-run' "$log_file"; then
  echo "quota switch script unexpectedly executed" >&2
  exit 1
fi
if grep -q 'codex-quota-should-not-run' "$log_file"; then
  echo "codex-quota unexpectedly executed" >&2
  exit 1
fi
grep -q 'shared heartbeat loop end status=0' "$log_file"
grep -q 'merged-pr catchup end status=0' "$log_file"
grep -q 'linked-pr issue catchup end status=0' "$log_file"
grep -q 'heartbeat-loop-ran' "$log_file"
grep -q 'catchup-ran' "$log_file"
grep -q 'issue-link-catchup-ran' "$log_file"

echo "heartbeat-safe-auto no-tmux-session test passed"
