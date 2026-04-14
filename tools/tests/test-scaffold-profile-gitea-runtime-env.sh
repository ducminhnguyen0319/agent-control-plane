#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCAFFOLD_BIN="${ROOT_DIR}/tools/bin/scaffold-profile.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

profile_home="${tmpdir}/profiles"

output="$(
  bash "${SCAFFOLD_BIN}" \
    --profile-id gitea-smoke \
    --repo-slug acp-admin/demo \
    --forge-provider gitea \
    --gitea-base-url http://127.0.0.1:3300 \
    --gitea-token local-token \
    --repo-root "${tmpdir}/repo" \
    --agent-root "${tmpdir}/runtime/gitea-smoke" \
    --worktree-root "${tmpdir}/worktrees" \
    --profile-home "${profile_home}"
)"

profile_yaml="$(awk -F= '/^PROFILE_YAML=/{print $2; exit}' <<<"${output}")"
runtime_env="$(awk -F= '/^PROFILE_RUNTIME_ENV=/{print $2; exit}' <<<"${output}")"

test -f "${profile_yaml}"
test -f "${runtime_env}"

grep -q '^  source: "gitea"$' "${profile_yaml}"
grep -q '^ACP_FORGE_PROVIDER=gitea$' "${runtime_env}"
grep -q '^ACP_GITEA_BASE_URL=http://127.0.0.1:3300$' "${runtime_env}"
grep -q '^ACP_GITEA_TOKEN=local-token$' "${runtime_env}"
grep -q '^ACP_SOURCE_SYNC_REMOTE=gitea$' "${runtime_env}"

echo "scaffold profile gitea runtime env test passed"
