#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUTBOX_BIN="${FLOW_ROOT}/tools/bin/github-write-outbox.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

bin_dir="$tmpdir/bin"
state_root="$tmpdir/state"
post_log="$tmpdir/post.json"
mkdir -p "$bin_dir" "$state_root"

cat >"$bin_dir/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

route="${2:-}"
if [[ "${1:-}" != "api" ]]; then
  echo "unexpected gh args: $*" >&2
  exit 1
fi

case "${route}" in
  repositories/99/pulls/88/reviews?per_page=100|repos/example/repo/pulls/88/reviews?per_page=100)
    printf '[]\n'
    ;;
  repositories/99/pulls/88/reviews|repos/example/repo/pulls/88/reviews)
    input_file=""
    prev=""
    for arg in "$@"; do
      if [[ "${prev}" == "--input" ]]; then
        input_file="${arg}"
        break
      fi
      prev="${arg}"
    done
    cat "${input_file}" >"${TEST_POST_LOG:?}"
    printf '{}\n'
    ;;
  *)
    echo "unexpected gh route: $*" >&2
    exit 1
    ;;
esac
EOF

chmod +x "$bin_dir/gh"

export PATH="$bin_dir:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export ACP_STATE_ROOT="$state_root"
export F_LOSNING_STATE_ROOT="$state_root"
export ACP_REPO_ID="99"
export ACP_REPO_SLUG="example/repo"
export FLOW_GITHUB_GRAPHQL_AVAILABLE_CACHE="no"
export TEST_POST_LOG="$post_log"

bash "$OUTBOX_BIN" enqueue-approval \
  --repo-slug example/repo \
  --number 88 \
  --body "Local-first PR approval body" >/dev/null

pending_file="$(find "$state_root/github-outbox/pending" -type f -name 'approval-*.json' | head -n 1)"
test -n "$pending_file"
jq -e '.type == "approval"' "$pending_file" >/dev/null
jq -e '.number == "88"' "$pending_file" >/dev/null

bash "$OUTBOX_BIN" flush --limit 10 >/dev/null

if find "$state_root/github-outbox/pending" -type f -name '*.json' | grep -q .; then
  echo "pending GitHub approval outbox items were not flushed" >&2
  exit 1
fi

sent_file="$(find "$state_root/github-outbox/sent" -type f -name 'approval-*.json' | head -n 1)"
test -n "$sent_file"
jq -e '.event == "APPROVE"' "$post_log" >/dev/null
jq -e '.body == "Local-first PR approval body"' "$post_log" >/dev/null

echo "github write outbox flushes PR approval test passed"
