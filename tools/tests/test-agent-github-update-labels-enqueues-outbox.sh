#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
UPDATE_LABELS_BIN="${FLOW_ROOT}/tools/bin/agent-github-update-labels"
OUTBOX_BIN="${FLOW_ROOT}/tools/bin/github-write-outbox.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

bin_dir="$tmpdir/bin"
state_root="$tmpdir/state"
patch_log="$tmpdir/patch.json"
mkdir -p "$bin_dir" "$state_root"

cat >"$bin_dir/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

route="${2:-}"
mode="${TEST_GH_MODE:-offline}"

if [[ "${1:-}" != "api" ]]; then
  echo "unexpected gh args: $*" >&2
  exit 1
fi

if [[ "${route}" == "rate_limit" ]]; then
  cat <<'JSON'
{"resources":{"graphql":{"remaining":5000},"core":{"remaining":5000,"reset":4102444800}}}
JSON
  exit 0
fi

case "${route}" in
  repositories/99/issues/42|repos/example/repo/issues/42)
    if [[ "${mode}" == "offline" ]]; then
      echo "temporary network failure" >&2
      exit 1
    fi

    if [[ " $* " == *" --method PATCH "* ]]; then
      input_file=""
      prev=""
      for arg in "$@"; do
        if [[ "${prev}" == "--input" ]]; then
          input_file="${arg}"
          break
        fi
        prev="${arg}"
      done
      cat "${input_file}" >"${TEST_PATCH_LOG:?}"
      printf '{}\n'
      exit 0
    fi

    cat <<'JSON'
{"labels":[{"name":"agent-blocked"}]}
JSON
    exit 0
    ;;
esac

echo "unexpected gh route: $*" >&2
exit 1
EOF

chmod +x "$bin_dir/gh"

export PATH="$bin_dir:${PATH:-/usr/bin:/bin:/usr/sbin:/sbin}"
export ACP_STATE_ROOT="$state_root"
export F_LOSNING_STATE_ROOT="$state_root"
export ACP_REPO_ID="99"
export ACP_REPO_SLUG="example/repo"
export TEST_PATCH_LOG="$patch_log"
export FLOW_GITHUB_GRAPHQL_AVAILABLE_CACHE="no"

TEST_GH_MODE=offline bash "$UPDATE_LABELS_BIN" \
  --repo-slug example/repo \
  --number 42 \
  --add agent-running \
  --remove agent-blocked

pending_file="$(find "$state_root/github-outbox/pending" -type f -name '*.json' | head -n 1)"
test -n "$pending_file"
jq -e '.type == "labels"' "$pending_file" >/dev/null
jq -e '.repo_slug == "example/repo"' "$pending_file" >/dev/null
jq -e '.number == "42"' "$pending_file" >/dev/null
jq -e '.add == ["agent-running"]' "$pending_file" >/dev/null
jq -e '.remove == ["agent-blocked"]' "$pending_file" >/dev/null

TEST_GH_MODE=online bash "$OUTBOX_BIN" flush --limit 10 >/dev/null

if find "$state_root/github-outbox/pending" -type f -name '*.json' | grep -q .; then
  echo "pending GitHub label outbox items were not flushed" >&2
  exit 1
fi

sent_file="$(find "$state_root/github-outbox/sent" -type f -name '*.json' | head -n 1)"
test -n "$sent_file"
jq -e '.labels == ["agent-running"]' "$patch_log" >/dev/null

echo "agent-github-update-labels enqueues outbox test passed"
