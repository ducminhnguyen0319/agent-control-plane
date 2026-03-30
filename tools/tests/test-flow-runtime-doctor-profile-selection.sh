#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${FLOW_ROOT}/tools/bin/flow-runtime-doctor.sh"
SCAFFOLD_SCRIPT="${FLOW_ROOT}/tools/bin/scaffold-profile.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

profile_home="$tmpdir/profiles"
repo_slug="example-owner/alpha"

bash "$SCAFFOLD_SCRIPT" --profile-home "$profile_home" --profile-id alpha --repo-slug "$repo_slug" >/dev/null
bash "$SCAFFOLD_SCRIPT" --profile-home "$profile_home" --profile-id demo --repo-slug example/demo-platform >/dev/null
profile_notes_real="$(cd "$profile_home/alpha" && pwd -P)/README.md"

output="$(ACP_PROFILE_REGISTRY_ROOT="$profile_home" bash "$SCRIPT")"

grep -q '^PROFILE_ID=alpha$' <<<"$output"
grep -q '^PROFILE_SELECTION_MODE=implicit-default$' <<<"$output"
grep -q "^PROFILE_REGISTRY_ROOT=${profile_home}$" <<<"$output"
grep -q "^PROFILE_NOTES=${profile_notes_real}$" <<<"$output"
grep -q '^PROFILE_NOTES_EXISTS=yes$' <<<"$output"
grep -q '^PROFILE_SELECTION_NEXT_STEP=ACP_PROJECT_ID=<id> bash .*/tools/bin/render-flow-config.sh$' <<<"$output"

echo "flow runtime doctor profile selection test passed"
