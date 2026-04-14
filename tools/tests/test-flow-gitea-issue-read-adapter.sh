#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REAL_CONFIG_LIB="${FLOW_ROOT}/tools/bin/flow-config-lib.sh"
REAL_SHELL_LIB="${FLOW_ROOT}/tools/bin/flow-shell-lib.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

bin_dir="$tmpdir/bin"
mkdir -p "$bin_dir"

cp "$REAL_CONFIG_LIB" "$bin_dir/flow-config-lib.sh"
cp "$REAL_SHELL_LIB" "$bin_dir/flow-shell-lib.sh"

cat >"$bin_dir/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

args=("$@")
url="${args[$(( ${#args[@]} - 1 ))]}"

case "${url}" in
  "http://gitea.test/api/v1/repos/example/repo/issues?state=open&page=1&limit=100")
    cat <<'JSON'
[{"number":1,"title":"Local forge issue","html_url":"http://gitea.test/example/repo/issues/1","created_at":"2026-04-14T06:00:00Z","updated_at":"2026-04-14T06:10:00Z","labels":[{"name":"agent-keep-open"}]}]
JSON
    ;;
  "http://gitea.test/api/v1/repos/example/repo/issues/1")
    cat <<'JSON'
{"number":1,"state":"open","title":"Local forge issue","body":"Mirror me","html_url":"http://gitea.test/example/repo/issues/1","created_at":"2026-04-14T06:00:00Z","updated_at":"2026-04-14T06:10:00Z","labels":[{"name":"agent-keep-open"}]}
JSON
    ;;
  "http://gitea.test/api/v1/repos/example/repo/issues/1/comments?page=1&limit=100")
    cat <<'JSON'
[{"body":"Local comment","created_at":"2026-04-14T06:11:00Z","updated_at":"2026-04-14T06:12:00Z","html_url":"http://gitea.test/example/repo/issues/1#issuecomment-1"}]
JSON
    ;;
  *)
    echo "unexpected curl url: ${url}" >&2
    exit 97
    ;;
esac
EOF

chmod +x "$bin_dir/flow-config-lib.sh" "$bin_dir/flow-shell-lib.sh" "$bin_dir/curl"

LIB_PATH="$bin_dir/flow-config-lib.sh" \
PATH="$bin_dir:/usr/bin:/bin:/usr/sbin:/sbin" \
ACP_FORGE_PROVIDER="gitea" \
ACP_GITEA_BASE_URL="http://gitea.test" \
ACP_GITEA_TOKEN="test-token" \
bash <<'EOF'
set -euo pipefail
source "$LIB_PATH"

issues_json="$(flow_github_issue_list_json "example/repo" open 100)"
issue_json="$(flow_github_issue_view_json "example/repo" 1)"

jq -e 'length == 1' >/dev/null <<<"$issues_json"
jq -e '.[0].number == 1' >/dev/null <<<"$issues_json"
jq -e '.[0].labels[0].name == "agent-keep-open"' >/dev/null <<<"$issues_json"

jq -e '.number == 1' >/dev/null <<<"$issue_json"
jq -e '.state == "OPEN"' >/dev/null <<<"$issue_json"
jq -e '.title == "Local forge issue"' >/dev/null <<<"$issue_json"
jq -e '.comments[0].body == "Local comment"' >/dev/null <<<"$issue_json"
EOF

echo "flow gitea issue read adapter test passed"
