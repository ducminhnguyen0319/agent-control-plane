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
  "http://gitea.test/api/v1/repos/example/repo/issues/1")
    cat <<'JSON'
{"number":1,"state":"open","title":"Public forge issue","body":"Mirror me","html_url":"http://gitea.test/example/repo/issues/1","created_at":"2026-04-14T06:00:00Z","updated_at":"2026-04-14T06:10:00Z","labels":[]}
JSON
    ;;
  "http://gitea.test/api/v1/repos/example/repo/issues/1/comments?page=1&limit=100")
    cat <<'JSON'
[]
JSON
    ;;
  "http://gitea.test/api/v1/repos/example/repo/pulls/7")
    cat <<'JSON'
{"number":7,"title":"Public forge PR","body":"PR body","html_url":"http://gitea.test/example/repo/pulls/7","created_at":"2026-04-14T06:00:00Z","updated_at":"2026-04-14T06:05:00Z","draft":false,"mergeable":true,"state":"open","merged":false,"merged_at":null,"user":{"login":"author-user"},"head":{"ref":"feature/public-pr","sha":"abc123"},"base":{"ref":"main"},"labels":[]}
JSON
    ;;
  "http://gitea.test/api/v1/repos/example/repo/issues/7/comments?page=1&limit=100")
    cat <<'JSON'
[{"body":"PR discussion","created_at":"2026-04-14T06:06:00Z","updated_at":"2026-04-14T06:07:00Z","html_url":"http://gitea.test/example/repo/pulls/7#issuecomment-1"}]
JSON
    ;;
  "http://gitea.test/api/v1/repos/example/repo/pulls/7/files?page=1&limit=100")
    cat <<'JSON'
[{"filename":"package.json"}]
JSON
    ;;
  "http://gitea.test/api/v1/repos/example/repo/pulls/7/reviews?page=1&limit=100")
    cat <<'JSON'
[]
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
bash <<'EOF'
set -euo pipefail
source "$LIB_PATH"

issue_json="$(flow_github_issue_view_json "example/repo" 1)"
pr_json="$(flow_github_pr_view_json "example/repo" 7)"

jq -e '.number == 1 and .state == "OPEN"' >/dev/null <<<"$issue_json"
jq -e '.number == 7 and .state == "OPEN" and .headRefOid == "abc123" and .files[0].path == "package.json"' >/dev/null <<<"$pr_json"
EOF

echo "flow gitea public read without auth test passed"
