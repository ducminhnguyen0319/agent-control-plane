#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PR_RISK_BIN="${FLOW_ROOT}/bin/pr-risk.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

bin_dir="$tmpdir/bin"
node_bin_dir="$(dirname "$(command -v node)")"
mkdir -p "$bin_dir"

cat >"$bin_dir/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

url="${@: -1}"
case "$url" in
  http://gitea.local/api/v1/repos/acp-admin/agent-control-plane/pulls/6)
    cat <<'JSON'
{"number":6,"title":"chore: tighten package reference surface","body":"Closes #4","state":"open","draft":false,"mergeable":true,"html_url":"http://gitea.local/acp-admin/agent-control-plane/pulls/6","user":{"login":"acp-admin"},"requested_reviewers":[],"base":{"ref":"main","sha":"86263b3"},"head":{"ref":"agent/agent-control-plane/issue-4-tighten-package-reference-surface","sha":"bc1d29f930c55a4f726f885c80569baa70960dd6"}}
JSON
    ;;
  http://gitea.local/api/v1/repos/acp-admin/agent-control-plane/issues/6/comments*)
    printf '[]\n'
    ;;
  http://gitea.local/api/v1/repos/acp-admin/agent-control-plane/pulls/6/files*)
    cat <<'JSON'
[{"filename":"package.json"},{"filename":"tools/tests/test-package-tarball-surface.sh"}]
JSON
    ;;
  http://gitea.local/api/v1/repos/acp-admin/agent-control-plane/pulls/6/reviews*)
    printf '[]\n'
    ;;
  http://gitea.local/api/v1/repos/acp-admin/agent-control-plane/commits/bc1d29f930c55a4f726f885c80569baa70960dd6)
    cat <<'JSON'
{"commit":{"committer":{"date":"2026-04-14T08:02:40Z"}}}
JSON
    ;;
  http://gitea.local/api/v1/repos/acp-admin/agent-control-plane/commits/bc1d29f930c55a4f726f885c80569baa70960dd6/check-runs*)
    printf '{"message":"not found"}\n'
    ;;
  *)
    echo "unexpected curl url: $url" >&2
    exit 1
    ;;
esac
EOF

chmod +x "$bin_dir/curl"

risk_json="$(
  PATH="$bin_dir:$node_bin_dir:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  ACP_FORGE_PROVIDER="gitea" \
  ACP_GITEA_BASE_URL="http://gitea.local" \
  ACP_GITEA_TOKEN="local-token" \
  F_LOSNING_REPO_SLUG="acp-admin/agent-control-plane" \
  bash "$PR_RISK_BIN" 6
)"

test "$(jq -r '.isManagedByAgent' <<<"$risk_json")" = "true"
test "$(jq -r '.linkedIssueId' <<<"$risk_json")" = "4"
test "$(jq -r '.risk' <<<"$risk_json")" = "critical-infra"
test "$(jq -r '.checksOk' <<<"$risk_json")" = "true"
test "$(jq -r '.agentLane' <<<"$risk_json")" = "double-check-1"
test "$(jq -r '.eligibleForAutoMerge' <<<"$risk_json")" = "false"

echo "pr-risk gitea forge view test passed"
