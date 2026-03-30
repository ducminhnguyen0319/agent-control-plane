#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${FLOW_ROOT}/tools/bin/sync-recurring-issue-checklist.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

bin_dir="$tmpdir/bin"
mkdir -p "$bin_dir"

patched_body_file="$tmpdir/patched-body.json"

cat >"$bin_dir/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

patched_body_file="${TEST_PATCHED_BODY_FILE:?}"

if [[ "${1:-}" == "issue" && "${2:-}" == "view" ]]; then
  cat <<'JSON'
{"number":42,"state":"OPEN","title":"Recurring checklist demo","body":"This is a recurring keep-open issue.\n\nChecklist:\n- [ ] Add a `completedRatio` field to the summary output.\n- [ ] Document one example command per output mode in `README.md`.\n","url":"https://example.test/issues/42","labels":[{"name":"agent-keep-open"}],"comments":[{"body":"Opened PR #11: https://example.test/pull/11","createdAt":"2026-03-27T10:00:00Z"},{"body":"Opened PR #12: https://example.test/pull/12","createdAt":"2026-03-27T11:00:00Z"}],"createdAt":"2026-03-27T09:00:00Z","updatedAt":"2026-03-27T11:00:00Z"}
JSON
  exit 0
fi

if [[ "${1:-}" == "pr" && "${2:-}" == "view" ]]; then
  pr_number="${3:-}"
  case "${pr_number}" in
    11)
      cat <<'JSON'
{"number":11,"title":"feat(task-metrics): add completedRatio to summary output","body":"Implements the completedRatio checklist item.","url":"https://example.test/pull/11","headRefName":"agent/demo/issue-42-completed-ratio","baseRefName":"main","mergeStateStatus":"MERGED","statusCheckRollup":[],"labels":[],"comments":[],"state":"MERGED","isDraft":false}
JSON
      ;;
    12)
      cat <<'JSON'
{"number":12,"title":"docs(readme): add example commands per output mode","body":"Adds README examples for each output mode.","url":"https://example.test/pull/12","headRefName":"agent/demo/issue-42-readme-examples","baseRefName":"main","mergeStateStatus":"MERGED","statusCheckRollup":[],"labels":[],"comments":[],"state":"MERGED","isDraft":false}
JSON
      ;;
    *)
      echo "unexpected pr view: $*" >&2
      exit 1
      ;;
  esac
  exit 0
fi

if [[ "${1:-}" == "api" ]]; then
  route="${2:-}"
  shift 2
  if [[ "${route}" == "repos/example/demo/issues/42" ]]; then
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
      cp "${input_file}" "$patched_body_file"
    else
      cat >"$patched_body_file"
    fi
    exit 0
  fi
fi

echo "unexpected gh args: $*" >&2
exit 1
EOF
chmod +x "$bin_dir/gh"

out="$(
  PATH="$bin_dir:$PATH" \
  TEST_PATCHED_BODY_FILE="$patched_body_file" \
  bash "$SCRIPT" --repo-slug example/demo --issue-id 42
)"

grep -q '^CHECKLIST_SYNC_STATUS=updated$' <<<"$out"
grep -q '^CHECKLIST_TOTAL=2$' <<<"$out"
grep -q '^CHECKLIST_CHECKED=2$' <<<"$out"
grep -q '^CHECKLIST_UNCHECKED=0$' <<<"$out"
grep -q '^CHECKLIST_MATCHED_PR_NUMBERS=11,12$' <<<"$out"

test -f "$patched_body_file"
jq -r '.body' "$patched_body_file" | grep -q -- '- \[x\] Add a `completedRatio` field to the summary output\.'
jq -r '.body' "$patched_body_file" | grep -q -- '- \[x\] Document one example command per output mode in `README.md`\.'

echo "sync recurring issue checklist test passed"
