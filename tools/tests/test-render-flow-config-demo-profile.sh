#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${FLOW_ROOT}/tools/bin/render-flow-config.sh"
SCAFFOLD_SCRIPT="${FLOW_ROOT}/tools/bin/scaffold-profile.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

profile_home="$tmpdir/profiles"
repo_slug="example-owner/alpha"

bash "$SCAFFOLD_SCRIPT" --profile-home "$profile_home" --profile-id alpha --repo-slug "$repo_slug" >/dev/null
bash "$SCAFFOLD_SCRIPT" --profile-home "$profile_home" --profile-id demo --repo-slug example/demo-platform >/dev/null
profile_notes_real="$(cd "$profile_home/demo" && pwd -P)/README.md"

output="$(
  ACP_PROFILE_REGISTRY_ROOT="$profile_home" \
  AGENT_PROJECT_ID="alpha" \
  ACP_PROJECT_ID="demo" \
  bash "$SCRIPT"
)"

grep -q "^CONFIG_YAML=${profile_home}/demo/control-plane.yaml$" <<<"$output"
grep -q '^PROFILE_ID=demo$' <<<"$output"
grep -q '^PROFILE_SELECTION_MODE=explicit$' <<<"$output"
grep -q "^PROFILE_NOTES=${profile_notes_real}$" <<<"$output"
grep -q '^PROFILE_NOTES_EXISTS=yes$' <<<"$output"
grep -Eq '^AVAILABLE_PROFILES=(demo,alpha|alpha,demo)$' <<<"$output"
grep -q '^EFFECTIVE_CODING_WORKER=openclaw$' <<<"$output"
grep -q '^EFFECTIVE_PROVIDER_QUOTA_COOLDOWNS=300,900,1800,3600$' <<<"$output"
grep -q '^EFFECTIVE_OPENCLAW_MODEL=openrouter/qwen/qwen3.6-plus-preview:free$' <<<"$output"
grep -q '^EFFECTIVE_AGENT_REPO_ROOT=/tmp/agent-control-plane-demo/repo$' <<<"$output"

echo "render flow config demo profile test passed"
