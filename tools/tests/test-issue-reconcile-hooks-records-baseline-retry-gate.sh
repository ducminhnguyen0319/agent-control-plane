#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOKS_FILE="${FLOW_ROOT}/hooks/issue-reconcile-hooks.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

bin_dir="$tmpdir/bin"
tools_dir="$tmpdir/tools/bin"
state_root="$tmpdir/state"
agent_repo_root="$tmpdir/agent-repo"
mkdir -p "$bin_dir" "$tools_dir" "$state_root/retries/issues" "$agent_repo_root"

git -C "$agent_repo_root" init -q -b main
git -C "$agent_repo_root" config user.name "ACP Test"
git -C "$agent_repo_root" config user.email "acp-test@example.com"
printf 'baseline\n' >"$agent_repo_root/README.md"
git -C "$agent_repo_root" add README.md
git -C "$agent_repo_root" commit -q -m "baseline"
baseline_head="$(git -C "$agent_repo_root" rev-parse HEAD)"

cat >"$bin_dir/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "issue" && "${2:-}" == "view" ]]; then
  cat <<'JSON'
{"number":255,"title":"Recurring issue","body":"","labels":[{"name":"agent-keep-open"}],"comments":[]}
JSON
  exit 0
fi

echo "unexpected gh args: $*" >&2
exit 1
EOF

cat >"$tools_dir/retry-state.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail

kind="\${1:-}"
item_id="\${2:-}"
action="\${3:-}"
reason="\${4:-}"

if [[ "\${kind}" != "issue" || "\${item_id}" != "255" ]]; then
  echo "unexpected retry-state args: \$*" >&2
  exit 1
fi

state_file="${state_root}/retries/issues/255.env"

case "\${action}" in
  schedule)
    cat >"\${state_file}" <<STATE
ATTEMPTS=1
NEXT_ATTEMPT_EPOCH=0
NEXT_ATTEMPT_AT=
LAST_REASON=\${reason}
UPDATED_AT=2026-04-02T16:30:00Z
STATE
    ;;
  clear)
    rm -f "\${state_file}"
    ;;
  get)
    cat "\${state_file}"
    ;;
  *)
    echo "unexpected action: \${action}" >&2
    exit 1
    ;;
esac
EOF

chmod +x "$bin_dir/gh" "$tools_dir/retry-state.sh"

export PATH="$bin_dir:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export F_LOSNING_REPO_SLUG="example/repo"
export ISSUE_ID="255"

# shellcheck source=/dev/null
source "$HOOKS_FILE"
FLOW_TOOLS_DIR="$tools_dir"
REPO_SLUG="example/repo"
STATE_ROOT="$state_root"
AGENT_REPO_ROOT="$agent_repo_root"
DEFAULT_BRANCH="main"
issue_has_schedule_cadence() { return 1; }

issue_schedule_retry "verification-guard-blocked"

grep -q '^LAST_REASON=verification-guard-blocked$' "$state_root/retries/issues/255.env"
grep -q "^BASELINE_HEAD_SHA=${baseline_head}$" "$state_root/retries/issues/255.env"

echo "issue reconcile hooks baseline retry gate test passed"
