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
{"number":501,"title":"docs: clarify local-first PR automation","url":"https://example.test/pr/501","body":"","isDraft":false,"headRefName":"codex/issue-501-local-first","baseRefName":"main","labels":[],"files":[{"path":"docs/auto-flow.md"}],"mergeStateStatus":"CLEAN","reviewDecision":"","reviewRequests":[],"statusCheckRollup":[],"comments":[]}
JSON
  exit 0
fi

if [[ "${1:-}" == "api" ]]; then
  case "${2:-}" in
    repos/example/repo/pulls/501)
      printf 'abc123\n'
      exit 0
      ;;
    repos/example/repo/commits/abc123)
      printf '2026-03-15T20:30:00Z\n'
      exit 0
      ;;
    repos/example/repo/pulls/501/comments)
      printf '[]\n'
      exit 0
      ;;
    repos/example/repo/commits/abc123/check-runs)
      printf '{"check_runs":[]}\n'
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
  F_LOSNING_REPO_SLUG="example/repo" \
  bash "$PR_RISK_BIN" 501
)"

test "$(jq -r '.isManagedByAgent' <<<"$risk_json")" = "true"
test "$(jq -r '.linkedIssueId' <<<"$risk_json")" = "501"
test "$(jq -r '.noChecksReported' <<<"$risk_json")" = "true"
test "$(jq -r '.agentLane' <<<"$risk_json")" = "automerge"
test "$(jq -r '.eligibleForAutoMerge' <<<"$risk_json")" = "true"

if jq -e '.missingReasons[]? | select(. == "no-checks-reported")' >/dev/null <<<"$risk_json"; then
  echo "managed local-first PR unexpectedly blocked on missing GitHub checks" >&2
  printf '%s\n' "$risk_json" >&2
  exit 1
fi

echo "pr-risk local-first no-checks test passed"
