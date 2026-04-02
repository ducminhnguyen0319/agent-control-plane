#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOKS_FILE="${FLOW_ROOT}/hooks/heartbeat-hooks.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

node_bin_dir="$(dirname "$(command -v node)")"
bin_dir="$tmpdir/bin"
tools_dir="$tmpdir/tools/bin"
labels_log="$tmpdir/labels.log"

mkdir -p "$bin_dir" "$tools_dir"

cat >"$bin_dir/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "pr" && "${2:-}" == "list" ]]; then
  printf '[]\n'
  exit 0
fi

if [[ "${1:-}" == "issue" && "${2:-}" == "view" ]]; then
  case "${3:-}" in
    102)
      cat <<'JSON'
{"number":102,"title":"Manual blocked issue","body":"","labels":[{"name":"agent-blocked"}],"comments":[]}
JSON
      ;;
    104)
      cat <<'JSON'
{"number":104,"title":"Orphan blocked issue","body":"","labels":[{"name":"agent-blocked"}],"comments":[{"body":"# Blocker: Worker session failed before publish\n\nThe worker exited before ACP could publish or reconcile a result for this cycle.\n\nFailure reason:\n- `claude-exit-failed`\n\nNext step:\n- inspect the run logs for this session and re-queue once the underlying worker issue is resolved"}]}
JSON
      ;;
    *)
      echo "unexpected issue view args: $*" >&2
      exit 1
      ;;
  esac
  exit 0
fi

if [[ "${1:-}" == "issue" && "${2:-}" == "list" ]]; then
  cat <<'JSON'
[
  {"number":101,"createdAt":"2026-03-15T10:00:00Z","labels":[]},
  {"number":102,"createdAt":"2026-03-15T10:01:00Z","labels":[{"name":"agent-blocked"}]},
  {"number":103,"createdAt":"2026-03-15T10:02:00Z","labels":[{"name":"agent-blocked"}]},
  {"number":104,"createdAt":"2026-03-15T10:03:00Z","labels":[{"name":"agent-blocked"}]}
]
JSON
  exit 0
fi

echo "unexpected gh args: $*" >&2
exit 1
EOF

cat >"$tools_dir/retry-state.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

kind="${1:-}"
item_id="${2:-}"
action="${3:-}"

if [[ "$kind" != "issue" || "$action" != "get" ]]; then
  echo "unexpected retry-state args: $*" >&2
  exit 1
fi

case "$item_id" in
  102)
    cat <<'OUT'
KIND=issue
ITEM_ID=102
ATTEMPTS=0
NEXT_ATTEMPT_EPOCH=0
NEXT_ATTEMPT_AT=
READY=yes
LAST_REASON=
UPDATED_AT=
OUT
    ;;
  103)
    cat <<'OUT'
KIND=issue
ITEM_ID=103
ATTEMPTS=1
NEXT_ATTEMPT_EPOCH=0
NEXT_ATTEMPT_AT=
READY=yes
LAST_REASON=scope-guard-blocked
UPDATED_AT=2026-03-15T10:05:00Z
OUT
    ;;
  104)
    cat <<'OUT'
KIND=issue
ITEM_ID=104
ATTEMPTS=2
NEXT_ATTEMPT_EPOCH=0
NEXT_ATTEMPT_AT=
READY=yes
LAST_REASON=issue-worker-blocked
UPDATED_AT=2026-03-15T10:06:00Z
OUT
    ;;
  *)
    cat <<OUT
KIND=issue
ITEM_ID=${item_id}
ATTEMPTS=0
NEXT_ATTEMPT_EPOCH=0
NEXT_ATTEMPT_AT=
READY=yes
LAST_REASON=
UPDATED_AT=
OUT
    ;;
esac
EOF

cat >"$tools_dir/agent-github-update-labels" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >"${TEST_LABELS_LOG:?}"
EOF

chmod +x "$bin_dir/gh" "$tools_dir/retry-state.sh" "$tools_dir/agent-github-update-labels"

export PATH="$bin_dir:$node_bin_dir:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export TEST_LABELS_LOG="$labels_log"
export F_LOSNING_REPO_SLUG="example/repo"

# shellcheck source=/dev/null
source "$HOOKS_FILE"
FLOW_TOOLS_DIR="$tools_dir"
REPO_SLUG="example/repo"

ready_issue_ids="$(heartbeat_list_ready_issue_ids)"
blocked_recovery_issue_ids="$(heartbeat_list_blocked_recovery_issue_ids)"

grep -q '^101$' <<<"$ready_issue_ids"
if grep -q '^102$' <<<"$ready_issue_ids"; then
  echo "manual blocked issue unexpectedly returned as ready" >&2
  exit 1
fi
if grep -q '^103$' <<<"$ready_issue_ids"; then
  echo "blocked recovery issue unexpectedly returned as normal ready" >&2
  exit 1
fi
if grep -q '^104$' <<<"$ready_issue_ids"; then
  echo "orphan blocked issue unexpectedly returned as normal ready" >&2
  exit 1
fi

grep -q '^103$' <<<"$blocked_recovery_issue_ids"
grep -q '^104$' <<<"$blocked_recovery_issue_ids"
if grep -q '^102$' <<<"$blocked_recovery_issue_ids"; then
  echo "manual blocked issue unexpectedly returned as blocked-recovery candidate" >&2
  exit 1
fi

heartbeat_mark_issue_running 103 no
grep -q -- '--remove agent-blocked' "$labels_log"
grep -q -- '--add agent-running' "$labels_log"

echo "heartbeat ready blocked-recovery issue test passed"
