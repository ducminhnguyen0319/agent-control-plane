#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CATALOG_SCRIPT="${FLOW_ROOT}/tools/bin/workflow-catalog.sh"
SCAFFOLD_SCRIPT="${FLOW_ROOT}/tools/bin/scaffold-profile.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

profile_home="$tmpdir/profiles"

bash "$SCAFFOLD_SCRIPT" --profile-home "$profile_home" --profile-id alpha --repo-slug example/alpha >/dev/null
bash "$SCAFFOLD_SCRIPT" --profile-home "$profile_home" --profile-id demo --repo-slug example/demo-platform >/dev/null

list_out="$(ACP_PROFILE_REGISTRY_ROOT="$profile_home" bash "$CATALOG_SCRIPT" list)"
grep -q '^issue-implementation' <<<"$list_out"
grep -q '^pr-review' <<<"$list_out"

profiles_out="$(ACP_PROFILE_REGISTRY_ROOT="$profile_home" bash "$CATALOG_SCRIPT" profiles)"
grep -q '^alpha$' <<<"$profiles_out"
grep -q '^demo$' <<<"$profiles_out"

context_out="$(ACP_PROFILE_REGISTRY_ROOT="$profile_home" bash "$CATALOG_SCRIPT" context)"
grep -q '^ACTIVE_PROFILE=alpha$' <<<"$context_out"
grep -q '^PROFILE_SELECTION_MODE=implicit-default$' <<<"$context_out"
grep -q '^PROFILE_NOTES=' <<<"$context_out"

show_out="$(ACP_PROFILE_REGISTRY_ROOT="$profile_home" bash "$CATALOG_SCRIPT" show pr-review)"
grep -q '^ACTIVE_PROFILE=alpha$' <<<"$show_out"
grep -q '^PROFILE_SELECTION_MODE=implicit-default$' <<<"$show_out"
grep -q '^ID=pr-review$' <<<"$show_out"
grep -q '^ENTRYPOINT=tools/bin/start-pr-review-worker.sh$' <<<"$show_out"

json_out="$(ACP_PROFILE_REGISTRY_ROOT="$profile_home" bash "$CATALOG_SCRIPT" json)"
grep -q '"control_plane": "agent-control-plane"' <<<"$json_out"
grep -q '"available_profiles": \[' <<<"$json_out"
grep -q '"active_profile": "alpha"' <<<"$json_out"
grep -q '"profile_selection_mode": "implicit-default"' <<<"$json_out"
grep -q '"demo"' <<<"$json_out"
grep -q '"id": "pr-fix"' <<<"$json_out"

echo "workflow catalog test passed"
