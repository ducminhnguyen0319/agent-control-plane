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
  case "${3:-}" in
    601)
      cat <<'JSON'
{"number":601,"title":"feat: queued repair label should stay informational","url":"https://example.test/pr/601","body":"","isDraft":false,"headRefName":"agent/acp/issue-601-fix-label-semantics","baseRefName":"main","labels":[{"name":"agent-repair-queued"}],"files":[{"path":"docs/auto-flow.md"}],"mergeStateStatus":"CLEAN","reviewDecision":"","reviewRequests":[],"statusCheckRollup":[],"comments":[]}
JSON
      exit 0
      ;;
    602)
      cat <<'JSON'
{"number":602,"title":"feat: manual fix override should force one more pass","url":"https://example.test/pr/602","body":"","isDraft":false,"headRefName":"agent/acp/issue-602-manual-fix-override","baseRefName":"main","labels":[{"name":"agent-manual-fix-override"}],"files":[{"path":"docs/auto-flow.md"}],"mergeStateStatus":"CLEAN","reviewDecision":"","reviewRequests":[],"statusCheckRollup":[],"comments":[]}
JSON
      exit 0
      ;;
  esac
fi

if [[ "${1:-}" == "api" ]]; then
  case "${2:-}" in
    repos/example/repo/pulls/601)
      printf 'sha601\n'
      exit 0
      ;;
    repos/example/repo/commits/sha601)
      printf '2026-03-15T20:30:00Z\n'
      exit 0
      ;;
    repos/example/repo/pulls/601/comments)
      printf '[]\n'
      exit 0
      ;;
    repos/example/repo/commits/sha601/check-runs)
      printf '{"check_runs":[]}\n'
      exit 0
      ;;
    repos/example/repo/pulls/602)
      printf 'sha602\n'
      exit 0
      ;;
    repos/example/repo/commits/sha602)
      printf '2026-03-15T20:35:00Z\n'
      exit 0
      ;;
    repos/example/repo/pulls/602/comments)
      printf '[]\n'
      exit 0
      ;;
    repos/example/repo/commits/sha602/check-runs)
      printf '{"check_runs":[]}\n'
      exit 0
      ;;
  esac
fi

echo "unexpected gh args: $*" >&2
exit 1
EOF

chmod +x "$bin_dir/gh"

queued_json="$(
  PATH="$bin_dir:$node_bin_dir:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  ACP_MANAGED_PR_BRANCH_GLOBS="agent/acp/* codex/* openclaw/*" \
  F_LOSNING_REPO_SLUG="example/repo" \
  bash "$PR_RISK_BIN" 601
)"

test "$(jq -r '.hasRepairQueuedLabel' <<<"$queued_json")" = "true"
test "$(jq -r '.hasManualFixNeededLabel' <<<"$queued_json")" = "false"
test "$(jq -r '.hasManualFixOverride' <<<"$queued_json")" = "false"
test "$(jq -r '.agentLane' <<<"$queued_json")" = "automerge"
test "$(jq -r '.eligibleForAutoMerge' <<<"$queued_json")" = "true"
if jq -e '.missingReasons[]? | select(. == "manual-fix-override")' >/dev/null <<<"$queued_json"; then
  echo "queued repair label unexpectedly acted like a manual override" >&2
  printf '%s\n' "$queued_json" >&2
  exit 1
fi

manual_json="$(
  PATH="$bin_dir:$node_bin_dir:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  ACP_MANAGED_PR_BRANCH_GLOBS="agent/acp/* codex/* openclaw/*" \
  F_LOSNING_REPO_SLUG="example/repo" \
  bash "$PR_RISK_BIN" 602
)"

test "$(jq -r '.hasRepairQueuedLabel' <<<"$manual_json")" = "false"
test "$(jq -r '.hasManualFixNeededLabel' <<<"$manual_json")" = "false"
test "$(jq -r '.hasManualFixOverrideLabel' <<<"$manual_json")" = "true"
test "$(jq -r '.hasManualFixOverride' <<<"$manual_json")" = "true"
test "$(jq -r '.agentLane' <<<"$manual_json")" = "fix"
if ! jq -e '.missingReasons[]? | select(. == "manual-fix-override")' >/dev/null <<<"$manual_json"; then
  echo "manual fix override label did not force the fix lane" >&2
  printf '%s\n' "$manual_json" >&2
  exit 1
fi

echo "pr-risk fix label semantics test passed"
