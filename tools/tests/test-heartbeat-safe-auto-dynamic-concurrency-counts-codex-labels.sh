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
cache_dir="$tmpdir/cache"
log_file="$tmpdir/heartbeat.log"
quota_cache="$cache_dir/codex-full-quota.json"
profile_home="$tmpdir/profiles"

mkdir -p \
  "$flow_root/tools/bin" \
  "$flow_root/hooks" \
  "$shared_home/skills/openclaw/codex-quota-manager/scripts" \
  "$bin_dir" \
  "$agent_root/runs" \
  "$agent_root/state" \
  "$memory_dir" \
  "$cache_dir" \
  "$profile_home"

cp "$SOURCE_SCRIPT" "$flow_root/tools/bin/heartbeat-safe-auto.sh"
cp "$FLOW_CONFIG_LIB" "$flow_root/tools/bin/flow-config-lib.sh"
cp "$FLOW_LIB" "$flow_root/tools/bin/flow-shell-lib.sh"

cat >"$quota_cache" <<'EOF'
[
  {
    "label": "mihanh",
    "accountId": "acct-team",
    "planType": "team",
    "usage": {
      "rate_limit": {
        "limit_reached": false,
        "primary_window": { "used_percent": 12 },
        "secondary_window": { "used_percent": 18 }
      }
    }
  },
  {
    "label": "mihanh1",
    "accountId": "acct-team",
    "planType": "plus",
    "usage": {
      "rate_limit": {
        "limit_reached": false,
        "primary_window": { "used_percent": 22 },
        "secondary_window": { "used_percent": 15 }
      }
    }
  },
  {
    "label": "admin1",
    "accountId": "acct-plus",
    "planType": "plus",
    "usage": {
      "rate_limit": {
        "limit_reached": false,
        "primary_window": { "used_percent": 31 },
        "secondary_window": { "used_percent": 21 }
      }
    }
  }
]
EOF

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
printf 'heartbeat-loop-args=%s\n' "$*"
EOF

cat >"$flow_root/tools/bin/agent-project-catch-up-merged-prs" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'catchup-ran\n'
EOF

cat >"$flow_root/hooks/heartbeat-hooks.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
EOF

cat >"$shared_home/skills/openclaw/codex-quota-manager/scripts/auto-switch.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'quota-switch-check-ok\n'
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

cat >"$bin_dir/codex-quota" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF

chmod +x \
  "$flow_root/tools/bin/flow-shell-lib.sh" \
  "$flow_root/tools/bin/flow-config-lib.sh" \
  "$flow_root/tools/bin/heartbeat-safe-auto.sh" \
  "$flow_root/tools/bin/audit-retained-worktrees.sh" \
  "$flow_root/tools/bin/audit-agent-worktrees.sh" \
  "$flow_root/tools/bin/agent-project-heartbeat-loop" \
  "$flow_root/tools/bin/agent-project-catch-up-merged-prs" \
  "$flow_root/hooks/heartbeat-hooks.sh" \
  "$shared_home/skills/openclaw/codex-quota-manager/scripts/auto-switch.sh" \
  "$bin_dir/tmux" \
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
CODEX_QUOTA_MANAGER_FULL_CACHE_FILE="$quota_cache" \
bash "$flow_root/tools/bin/heartbeat-safe-auto.sh" >"$log_file"

grep -q 'HEALTHY_QUOTA_POOLS=3' "$log_file"
grep -q 'EFFECTIVE_MAX_CONCURRENT_WORKERS=8' "$log_file"
grep -q 'EFFECTIVE_MAX_CONCURRENT_PR_WORKERS=4' "$log_file"
grep -q 'EFFECTIVE_MAX_RECURRING_ISSUE_WORKERS=3' "$log_file"

echo "heartbeat-safe-auto dynamic concurrency counts codex labels test passed"
