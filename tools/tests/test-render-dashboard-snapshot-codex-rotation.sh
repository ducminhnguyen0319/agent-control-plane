#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SNAPSHOT_BIN="${FLOW_ROOT}/tools/dashboard/dashboard_snapshot.py"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

profile_registry_root="$tmpdir/profiles"
profile_dir="$profile_registry_root/demo"
runs_root="$tmpdir/runtime/demo/runs"
state_root="$tmpdir/runtime/demo/state"
cache_root="$tmpdir/cache"
bin_dir="$tmpdir/bin"

mkdir -p \
  "$profile_dir" \
  "$runs_root" \
  "$state_root" \
  "$cache_root/codex-quota-manager" \
  "$bin_dir"

cat >"$profile_dir/control-plane.yaml" <<EOF
schema_version: "1"
id: "demo"
repo:
  slug: "example/demo-codex"
  root: "$tmpdir/repo"
  default_branch: "main"
runtime:
  orchestrator_agent_root: "$tmpdir/runtime/demo"
  worktree_root: "$tmpdir/worktrees"
  agent_repo_root: "$tmpdir/repo"
  runs_root: "$runs_root"
  state_root: "$state_root"
  history_root: "$tmpdir/runtime/demo/history"
execution:
  coding_worker: "codex"
  safe_profile: "demo_safe"
  bypass_profile: "demo_bypass"
EOF

# admin1 must have a future next_retry_at so the dashboard sees it as
# "deferred" rather than "ready" — otherwise next_retry_label stays empty.
admin1_retry_at=$(( $(date +%s) + 86400 ))
cat >"$cache_root/codex-quota-manager/rotation-state.json" <<EOF
{
  "accounts": {
    "mihanh": { "removed": false, "next_retry_at": 1775176192, "last_reason": "usage-limit" },
    "mihanh1": { "removed": false, "next_retry_at": 0, "last_reason": "switched" },
    "admin1": { "removed": false, "next_retry_at": ${admin1_retry_at}, "last_reason": "usage-limit" }
  }
}
EOF

cat >"$cache_root/codex-quota-manager/last-switch.env" <<'EOF'
LAST_SWITCH_EPOCH=1775127249
LAST_SWITCH_LABEL=mihanh1
LAST_SWITCH_REASON=usage-limit
EOF

cat >"$bin_dir/codex-quota" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "codex" && "${2:-}" == "list" && "${3:-}" == "--json" ]]; then
  cat <<JSON
{"activeInfo":{"trackedLabel":"mihanh"},"accounts":[{"label":"mihanh","accountId":"acct-team","isActive":true},{"label":"mihanh1","accountId":"acct-team"},{"label":"admin1","accountId":"acct-plus"}]}
JSON
  exit 0
fi
exit 1
EOF
chmod +x "$bin_dir/codex-quota"

snapshot="$(
  PATH="$bin_dir:$PATH" \
  CODEX_QUOTA_BIN="$bin_dir/codex-quota" \
  XDG_CACHE_HOME="$cache_root" \
  ACP_PROFILE_REGISTRY_ROOT="$profile_registry_root" \
  python3 "$SNAPSHOT_BIN" --pretty
)"

grep -q '"active_label": "mihanh"' <<<"$snapshot"
grep -q '"candidate_labels": \[' <<<"$snapshot"
grep -q '"mihanh1"' <<<"$snapshot"
grep -q '"admin1"' <<<"$snapshot"
grep -q '"switch_decision": "ready-candidate"' <<<"$snapshot"
grep -q '"next_retry_label": "admin1"' <<<"$snapshot"
grep -q '"last_switch_label": "mihanh1"' <<<"$snapshot"

echo "render dashboard snapshot codex rotation test passed"
