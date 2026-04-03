#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SYNC_SCRIPT="${FLOW_ROOT}/tools/bin/sync-shared-agent-home.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

source_root="$tmpdir/source-home"
target_home="$tmpdir/runtime-home"
fake_bin="$tmpdir/bin"
rsync_log="$tmpdir/rsync.log"

mkdir -p \
  "$source_root/tools/bin" \
  "$source_root/skills/openclaw/codex-quota-manager/scripts" \
  "$fake_bin"

printf 'tool\n' >"$source_root/tools/bin/example.sh"
printf '#!/usr/bin/env bash\n' >"$source_root/skills/openclaw/codex-quota-manager/scripts/auto-switch.sh"
chmod +x "$source_root/skills/openclaw/codex-quota-manager/scripts/auto-switch.sh"

cat >"$fake_bin/rsync" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'rsync-called\n' >>"${ACP_TEST_RSYNC_LOG:?}"
exit 1
EOF
chmod +x "$fake_bin/rsync"

PATH="$fake_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
ACP_TEST_RSYNC_LOG="$rsync_log" \
  bash "$SYNC_SCRIPT" "$source_root" "$target_home" >/dev/null

grep -q 'rsync-called' "$rsync_log"
test -f "$target_home/tools/bin/example.sh"
test -f "$target_home/skills/openclaw/codex-quota-manager/scripts/auto-switch.sh"
test -f "$target_home/skills/openclaw/agent-control-plane/SKILL.md"
test -f "$target_home/skills/openclaw/agent-control-plane/assets/workflow-catalog.json"

echo "sync-shared-agent-home falls back when rsync fails test passed"
