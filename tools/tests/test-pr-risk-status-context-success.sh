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
{"number":701,"title":"fix(render-flow-config): keep profile YAML precedence intact","url":"https://example.test/pr/701","body":"Closes #701","isDraft":false,"headRefName":"agent/acp/issue-701-status-context-success","baseRefName":"main","labels":[],"files":[{"path":"tools/bin/render-flow-config.sh"}],"mergeStateStatus":"CLEAN","reviewDecision":"","reviewRequests":[],"statusCheckRollup":[{"__typename":"CheckRun","name":"package-and-docs","status":"COMPLETED","conclusion":"SUCCESS","workflowName":"CI"},{"__typename":"StatusContext","context":"security/snyk (example)","state":"SUCCESS"}],"comments":[]}
JSON
  exit 0
fi

if [[ "${1:-}" == "api" ]]; then
  case "${2:-}" in
    repos/example/repo/pulls/701)
      printf 'sha701\n'
      exit 0
      ;;
    repos/example/repo/commits/sha701)
      printf '2026-03-15T20:35:00Z\n'
      exit 0
      ;;
    repos/example/repo/pulls/701/comments)
      printf '[]\n'
      exit 0
      ;;
    repos/example/repo/commits/sha701/check-runs)
      printf '{"check_runs":[{"name":"package-and-docs","status":"completed","conclusion":"success"}]}\n'
      exit 0
      ;;
  esac
fi

echo "unexpected gh args: $*" >&2
exit 1
EOF

chmod +x "$bin_dir/gh"

risk_json="$(
  PATH="$bin_dir:$node_bin_dir:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  ACP_MANAGED_PR_BRANCH_GLOBS="agent/acp/* codex/* openclaw/*" \
  F_LOSNING_REPO_SLUG="example/repo" \
  bash "$PR_RISK_BIN" 701
)"

test "$(jq -r '.isManagedByAgent' <<<"$risk_json")" = "true"
test "$(jq -r '.noChecksReported' <<<"$risk_json")" = "false"
test "$(jq -r '.checksOk' <<<"$risk_json")" = "true"
test "$(jq -r '.agentLane' <<<"$risk_json")" = "automerge"
test "$(jq -r '.eligibleForAutoMerge' <<<"$risk_json")" = "true"
test "$(jq -r '.pendingChecks | length' <<<"$risk_json")" = "0"

if jq -e '.missingReasons[]? | select(. == "undefined:status-")' >/dev/null <<<"$risk_json"; then
  echo "status context success was misclassified as a pending check" >&2
  printf '%s\n' "$risk_json" >&2
  exit 1
fi

echo "pr-risk status context success test passed"
