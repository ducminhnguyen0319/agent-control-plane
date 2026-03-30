#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${FLOW_ROOT}/bin/audit-issue-routing.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

bin_dir="$tmpdir/bin"
mkdir -p "$bin_dir"

cat >"$bin_dir/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "pr" && "${2:-}" == "list" ]]; then
  cat <<'JSON'
[
  {"headRefName":"agent/acp/issue-501-slice","body":"","labels":[],"comments":[]}
]
JSON
  exit 0
fi

if [[ "${1:-}" == "issue" && "${2:-}" == "list" ]]; then
  cat <<'JSON'
[
  {"number":501,"title":"linked issue","createdAt":"2026-03-15T10:00:00Z","updatedAt":"2026-03-15T10:15:00Z","labels":[{"name":"agent-running"}]},
  {"number":502,"title":"stale running issue","createdAt":"2026-03-15T10:05:00Z","updatedAt":"2026-03-15T10:20:00Z","labels":[{"name":"agent-running"}]}
]
JSON
  exit 0
fi

echo "unexpected gh args: $*" >&2
exit 1
EOF

chmod +x "$bin_dir/gh"

output="$(
  PATH="$bin_dir:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  F_LOSNING_REPO_SLUG="example/repo" \
  ACP_MANAGED_PR_BRANCH_GLOBS="agent/acp/* codex/* openclaw/*" \
  bash "$SCRIPT" 0
)"

grep -q $'^502\tstale-agent-running\t' <<<"$output"
if grep -q $'^501\t' <<<"$output"; then
  echo "issue linked by custom managed branch unexpectedly remained routable" >&2
  printf '%s\n' "$output" >&2
  exit 1
fi

echo "audit issue routing managed branch globs test passed"
