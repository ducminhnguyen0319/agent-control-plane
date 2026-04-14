#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLI_JS="${ROOT_DIR}/npm/bin/agent-control-plane.js"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

repo_root="${tmpdir}/repo"
platform_home="${tmpdir}/platform"
bin_dir="${tmpdir}/bin"
mkdir -p "${repo_root}/.git" "${platform_home}" "${bin_dir}"

for cmd in bash git jq python3 tmux node; do
  target="$(command -v "${cmd}")"
  ln -sf "${target}" "${bin_dir}/${cmd}"
done
ln -sf "$(command -v bash)" "${bin_dir}/codex"

output="$(
  PATH="${bin_dir}" \
  AGENT_PLATFORM_HOME="${platform_home}" \
  node "${CLI_JS}" setup \
    --dry-run \
    --non-interactive \
    --forge-provider gitea \
    --repo-slug acp-admin/demo \
    --gitea-base-url http://127.0.0.1:3300 \
    --gitea-token local-token \
    --repo-root "${repo_root}" \
    --coding-worker codex \
    2>&1
)"

grep -q '^SETUP_STATUS=dry-run$' <<<"${output}"
grep -q '^FORGE_PROVIDER=gitea$' <<<"${output}"
grep -q '^CORE_TOOLS_STATUS=ok$' <<<"${output}"
grep -q '^GITHUB_AUTH_STATUS=ok$' <<<"${output}"
if grep -q 'gh-missing' <<<"${output}"; then
  echo "setup dry-run unexpectedly required gh for gitea" >&2
  exit 1
fi

echo "agent control plane setup gitea dry-run without gh test passed"
