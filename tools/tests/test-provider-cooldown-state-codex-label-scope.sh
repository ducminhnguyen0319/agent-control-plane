#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${FLOW_ROOT}/tools/bin/provider-cooldown-state.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

state_root="$tmpdir/state"
config_file="$tmpdir/control-plane.yaml"
bin_dir="$tmpdir/bin"

mkdir -p "$bin_dir"

cat >"$config_file" <<EOF
id: "quota-demo"
runtime:
  orchestrator_agent_root: "${tmpdir}/agent"
  state_root: "${state_root}"
execution:
  coding_worker: "codex"
  provider_quota:
    cooldowns: "5,10"
  safe_profile: "f_losning_safe"
  bypass_profile: "f_losning_bypass"
EOF

cat >"$bin_dir/codex-quota" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "codex" && "${2:-}" == "list" && "${3:-}" == "--json" ]]; then
  cat <<JSON
{"activeInfo":{"trackedLabel":"mihanh1","activeLabel":"mihanh1"},"accounts":[{"label":"mihanh1","accountId":"acct-team"},{"label":"mihanh","accountId":"acct-team"}]}
JSON
  exit 0
fi
exit 1
EOF

chmod +x "$bin_dir/codex-quota"

schedule_output="$(
  PATH="$bin_dir:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  AGENT_CONTROL_PLANE_CONFIG="$config_file" \
  bash "$SCRIPT" schedule provider-quota-limit
)"

grep -q '^BACKEND=codex$' <<<"$schedule_output"
grep -q '^MODEL=f_losning_safe$' <<<"$schedule_output"
grep -q '^LABEL=mihanh1$' <<<"$schedule_output"
grep -q '^PROVIDER_KEY=codex-f_losning_safe-mihanh1$' <<<"$schedule_output"
test -f "$state_root/retries/providers/codex-f_losning_safe-mihanh1.env"
test ! -f "$state_root/retries/providers/codex-f_losning_safe.env"

echo "provider cooldown state codex label scope test passed"
