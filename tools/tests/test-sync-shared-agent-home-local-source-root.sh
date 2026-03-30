#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SYNC_SCRIPT="${FLOW_ROOT}/tools/bin/sync-shared-agent-home.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

source_home="$tmpdir/source-home"
target_home="$tmpdir/runtime-home"

mkdir -p \
  "$source_home/tools/bin" \
  "$source_home/skills/openclaw/codex-quota-manager/scripts"
mkdir -p "$source_home/.git/objects/aa"
printf 'fake-object\n' >"$source_home/.git/objects/aa/test"

cat >"$source_home/tools/bin/test-shared-tool" <<'INNER'
#!/usr/bin/env bash
set -euo pipefail
printf 'shared-tool-ok\n'
INNER

cat >"$source_home/skills/openclaw/codex-quota-manager/scripts/auto-switch.sh" <<'INNER'
#!/usr/bin/env bash
set -euo pipefail
printf 'quota-switch-ok\n'
INNER

chmod +x \
  "$source_home/tools/bin/test-shared-tool" \
  "$source_home/skills/openclaw/codex-quota-manager/scripts/auto-switch.sh"

mkdir -p \
  "$source_home/skills/openclaw/legacy-agent-control-plane/assets" \
  "$target_home/skills/openclaw/legacy-agent-control-plane/assets" \
  "$source_home/flows/project-adapters" \
  "$source_home/flows/profiles" \
  "$target_home/flows/project-adapters" \
  "$target_home/flows/profiles"
printf '{"control_plane":"stale"}\n' >"$source_home/skills/openclaw/legacy-agent-control-plane/assets/workflow-catalog.json"
printf '{"control_plane":"stale"}\n' >"$target_home/skills/openclaw/legacy-agent-control-plane/assets/workflow-catalog.json"
printf 'stale-source-publication\n' >"$source_home/flows/project-adapters/legacy-project.yaml"
printf 'stale-source-profile\n' >"$source_home/flows/profiles/legacy-project"
ln -s ../../skills/openclaw/legacy-agent-control-plane/assets/legacy-project.yaml "$target_home/flows/project-adapters/legacy-project.yaml"
printf 'stale-runtime-profile\n' >"$target_home/flows/profiles/legacy-project"

bash "$SYNC_SCRIPT" "$source_home" "$target_home" >/dev/null

test -f "$source_home/skills/openclaw/agent-control-plane/SKILL.md"
test -f "$source_home/skills/openclaw/agent-control-plane/assets/workflow-catalog.json"
test -f "$source_home/.git/objects/aa/test"
test ! -e "$source_home/skills/openclaw/agent-control-plane/profiles"
test ! -e "$source_home/skills/openclaw/legacy-agent-control-plane"
test ! -e "$source_home/flows/project-adapters"
test ! -e "$source_home/flows/profiles"
test -f "$target_home/skills/openclaw/agent-control-plane/SKILL.md"
test -f "$target_home/skills/openclaw/agent-control-plane/assets/workflow-catalog.json"
test ! -e "$target_home/.git"
test ! -e "$target_home/skills/openclaw/agent-control-plane/profiles"
test ! -e "$target_home/skills/openclaw/legacy-agent-control-plane"
test ! -e "$target_home/flows/project-adapters"
test ! -e "$target_home/flows/profiles"

echo "sync-shared-agent-home local source root test passed"
