#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SYNC_SCRIPT="${FLOW_ROOT}/tools/bin/sync-shared-agent-home.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

source_home="$tmpdir/source-home"
target_home="$tmpdir/runtime-home"

mkdir -p   "$source_home/tools/bin"   "$source_home/skills/openclaw/codex-quota-manager/scripts"   "$source_home/skills/openclaw/unrelated-skill/assets"   "$target_home/skills/openclaw/unrelated-skill/assets"

cat >"$source_home/tools/bin/test-shared-tool" <<'INNER'
#!/usr/bin/env bash
set -euo pipefail
printf 'shared-tool-ok
'
INNER

cat >"$source_home/skills/openclaw/codex-quota-manager/scripts/auto-switch.sh" <<'INNER'
#!/usr/bin/env bash
set -euo pipefail
printf 'quota-switch-ok
'
INNER

printf '# unrelated skill
' >"$source_home/skills/openclaw/unrelated-skill/SKILL.md"
printf '{"catalog":"keep"}
' >"$source_home/skills/openclaw/unrelated-skill/assets/workflow-catalog.json"
printf '# unrelated skill
' >"$target_home/skills/openclaw/unrelated-skill/SKILL.md"
printf '{"catalog":"keep"}
' >"$target_home/skills/openclaw/unrelated-skill/assets/workflow-catalog.json"

chmod +x   "$source_home/tools/bin/test-shared-tool"   "$source_home/skills/openclaw/codex-quota-manager/scripts/auto-switch.sh"

bash "$SYNC_SCRIPT" "$source_home" "$target_home" >/dev/null

test -f "$source_home/skills/openclaw/unrelated-skill/SKILL.md"
test -f "$source_home/skills/openclaw/unrelated-skill/assets/workflow-catalog.json"
test -f "$target_home/skills/openclaw/unrelated-skill/SKILL.md"
test -f "$target_home/skills/openclaw/unrelated-skill/assets/workflow-catalog.json"

echo "sync-shared-agent-home preserves unrelated workflow-catalog skill test passed"
