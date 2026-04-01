#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PR_RISK_BIN="${FLOW_ROOT}/bin/pr-risk.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

bin_dir="$tmpdir/bin"
node_bin_dir="$(dirname "$(command -v node)")"
mkdir -p "$bin_dir"

cat >"$bin_dir/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "pr" && "${2:-}" == "view" ]]; then
  cat <<'JSON'
{"number":702,"title":"fix(pr-risk): keep PR automation alive when REST is rate limited","url":"https://example.test/pr/702","body":"Closes #702","isDraft":false,"headRefName":"agent/acp/issue-702-rest-rate-limit","headRefOid":"deadbeef702","baseRefName":"main","labels":[],"files":[{"path":"tools/bin/render-flow-config.sh"}],"mergeStateStatus":"CLEAN","reviewDecision":"","reviewRequests":[],"statusCheckRollup":[{"__typename":"CheckRun","name":"package-and-docs","status":"COMPLETED","conclusion":"SUCCESS","workflowName":"CI"}],"comments":[]}
JSON
  exit 0
fi

if [[ "${1:-}" == "api" ]]; then
  echo "gh: API rate limit exceeded (HTTP 403)" >&2
  exit 1
fi

echo "unexpected gh args: $*" >&2
exit 1
EOF

chmod +x "$bin_dir/gh"

risk_json="$(
  PATH="$bin_dir:$node_bin_dir:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  ACP_MANAGED_PR_BRANCH_GLOBS="agent/acp/* codex/* openclaw/*" \
  F_LOSNING_REPO_SLUG="example/repo" \
  bash "$PR_RISK_BIN" 702
)"

test "$(jq -r '.isManagedByAgent' <<<"$risk_json")" = "true"
test "$(jq -r '.checksOk' <<<"$risk_json")" = "true"
test "$(jq -r '.agentLane' <<<"$risk_json")" = "automerge"
test "$(jq -r '.eligibleForAutoMerge' <<<"$risk_json")" = "true"
test "$(jq -r '.pendingChecks | length' <<<"$risk_json")" = "0"

echo "pr-risk graphql fallback when rest rate limited test passed"
