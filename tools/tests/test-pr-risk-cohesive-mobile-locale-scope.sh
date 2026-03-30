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
{"number":465,"title":"feat(mobile): align locale hydration with shared i18n contract","url":"https://example.test/pr/465","body":"Closes #422","isDraft":false,"headRefName":"codex/issue-422-mobile-align-language-selection-and-persisted-lo","baseRefName":"main","labels":[],"files":[{"path":"apps/mobile/README.md"},{"path":"apps/mobile/app/_layout.tsx"},{"path":"apps/mobile/app/settings/language.tsx"},{"path":"apps/mobile/app/settings/security.tsx"},{"path":"apps/mobile/src/components/LanguageSwitcher.tsx"},{"path":"apps/mobile/src/lib/i18n.ts"},{"path":"apps/mobile/src/lib/mobile-language-contract.ts"},{"path":"apps/mobile/src/lib/mobile-language.ts"},{"path":"apps/mobile/src/store/settings.ts"},{"path":"packages/i18n/README.md"},{"path":"packages/i18n/src/i18n.ts"}],"mergeStateStatus":"CLEAN","reviewDecision":"","reviewRequests":[],"statusCheckRollup":[],"comments":[]}
JSON
  exit 0
fi

if [[ "${1:-}" == "api" ]]; then
  case "${2:-}" in
    repos/example/repo/pulls/465)
      printf 'abc465\n'
      exit 0
      ;;
    repos/example/repo/commits/abc465)
      printf '2026-03-16T10:30:00Z\n'
      exit 0
      ;;
    repos/example/repo/pulls/465/comments)
      printf '[]\n'
      exit 0
      ;;
    repos/example/repo/commits/abc465/check-runs)
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
  bash "$PR_RISK_BIN" 465
)"

test "$(jq -r '.linkedIssueId' <<<"$risk_json")" = "422"
test "$(jq -r '.scopeTooBroad' <<<"$risk_json")" = "false"
test "$(jq -r '.mobileProductCount' <<<"$risk_json")" = "8"
test "$(jq -r '.agentLane' <<<"$risk_json")" = "automerge"
test "$(jq -r '.eligibleForAutoMerge' <<<"$risk_json")" = "true"

if jq -e '.missingReasons[]? | select(. == "scope-too-broad")' >/dev/null <<<"$risk_json"; then
  echo "cohesive mobile locale PR unexpectedly blocked on scope-too-broad" >&2
  printf '%s\n' "$risk_json" >&2
  exit 1
fi

echo "pr-risk cohesive mobile locale scope test passed"
