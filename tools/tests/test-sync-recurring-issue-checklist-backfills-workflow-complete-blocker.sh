#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${FLOW_ROOT}/tools/bin/sync-recurring-issue-checklist.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

bin_dir="$tmpdir/bin"
mkdir -p "$bin_dir"

cat >"$bin_dir/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

capture_file="${TEST_CAPTURE_FILE:?}"

if [[ "${1:-}" == "issue" && "${2:-}" == "view" ]]; then
  cat <<'JSON'
{"number":6,"state":"OPEN","title":"Recurring checklist demo","body":"Rolling summary metric improvements\n\nChecklist:\n- [x] Add an `overdueCount` field to the summary output.\n- [x] Add a helper that returns only tasks due within one day.\n- [ ] Expose `blockedCount` directly from the summary output.\n","url":"https://example.test/issues/6","labels":[{"name":"agent-keep-open"}],"comments":[{"body":"# Blocker: All checklist items already completed\n\nAll three checklist items for issue #6 are satisfied on the current baseline.","createdAt":"2026-03-28T17:39:37Z"}],"createdAt":"2026-03-28T10:00:00Z","updatedAt":"2026-03-28T17:39:37Z"}
JSON
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "view" ]]; then
  exit 1
fi

if [[ "${1:-}" == "api" ]]; then
  route="${2:-}"
  shift 2
  if [[ "${route}" == "repos/example/demo/issues/6" ]]; then
    input_file=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --input)
          input_file="${2:-}"
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    if [[ -n "${input_file}" && -f "${input_file}" ]]; then
      cp "${input_file}" "${capture_file}"
    else
      cat >"${capture_file}"
    fi
    exit 0
  fi
fi

echo "unexpected gh args: $*" >&2
exit 1
EOF
chmod +x "$bin_dir/gh"

TEST_CAPTURE_FILE="$tmpdir/update.txt" \
PATH="$bin_dir:$PATH" \
FLOW_GITHUB_GRAPHQL_AVAILABLE_CACHE="yes" \
bash "$SCRIPT" --repo-slug example/demo --issue-id 6 >"$tmpdir/out.txt"

grep -q '^CHECKLIST_SYNC_STATUS=updated$' "$tmpdir/out.txt"
grep -q '^CHECKLIST_TOTAL=3$' "$tmpdir/out.txt"
grep -q '^CHECKLIST_CHECKED=3$' "$tmpdir/out.txt"
grep -q '^CHECKLIST_UNCHECKED=0$' "$tmpdir/out.txt"
jq -r '.body' "$tmpdir/update.txt" | grep -q -- '- \[x\] Expose `blockedCount` directly from the summary output\.'

echo "sync recurring issue checklist workflow blocker backfill test passed"
