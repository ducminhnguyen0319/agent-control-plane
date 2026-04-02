#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SYNC_SCRIPT="${FLOW_ROOT}/tools/bin/sync-shared-agent-home.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

source_root="$tmpdir/source-skill-root"
target_home="$tmpdir/runtime-home"

mkdir -p \
  "$source_root/tools/bin" \
  "$source_root/assets" \
  "$source_root/bin" \
  "$source_root/hooks"
printf '# test skill\n' >"$source_root/SKILL.md"
printf '{}\n' >"$source_root/assets/workflow-catalog.json"
printf '#!/usr/bin/env bash\n' >"$source_root/bin/agent-control-plane"
printf '#!/usr/bin/env bash\n' >"$source_root/hooks/heartbeat-hooks.sh"
chmod +x "$source_root/bin/agent-control-plane" "$source_root/hooks/heartbeat-hooks.sh"

bash "$SYNC_SCRIPT" "$source_root" "$target_home" >/dev/null

test ! -e "$source_root/skills/openclaw/agent-control-plane"
test -f "$target_home/skills/openclaw/agent-control-plane/SKILL.md"
test -f "$target_home/skills/openclaw/agent-control-plane/assets/workflow-catalog.json"

echo "sync-shared-agent-home skill root source no nesting test passed"
