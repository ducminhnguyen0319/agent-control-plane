#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REAL_CONFIG_LIB="${FLOW_ROOT}/tools/bin/flow-config-lib.sh"
REAL_SHELL_LIB="${FLOW_ROOT}/tools/bin/flow-shell-lib.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

bin_dir="$tmpdir/bin"
body_file="$tmpdir/pr-body.md"
log_file="$tmpdir/curl.log"
mkdir -p "$bin_dir"

cat >"$body_file" <<'EOF'
Created from local Gitea PR adapter
EOF

cp "$REAL_CONFIG_LIB" "$bin_dir/flow-config-lib.sh"
cp "$REAL_SHELL_LIB" "$bin_dir/flow-shell-lib.sh"

cat >"$bin_dir/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

log_file="${TEST_CURL_LOG:?}"
printf '%s\n' "$*" >>"${log_file}"

args=("$@")
url="${args[$(( ${#args[@]} - 1 ))]}"
method="GET"
data_file=""
prev=""
for arg in "${args[@]}"; do
  if [[ "${prev}" == "-X" ]]; then
    method="${arg}"
  fi
  if [[ "${prev}" == "--data-binary" ]]; then
    data_file="${arg#@}"
  fi
  prev="${arg}"
done

case "${method}:${url}" in
  "GET:http://gitea.test/api/v1/user")
    cat <<'JSON'
{"login":"forge-admin"}
JSON
    ;;
  "GET:http://gitea.test/api/v1/repos/example/repo/pulls?state=open&page=1&limit=100")
    cat <<'JSON'
[{"number":7,"title":"Local forge PR","body":"PR body","html_url":"http://gitea.test/example/repo/pulls/7","created_at":"2026-04-14T06:00:00Z","merged_at":null,"draft":false,"head":{"ref":"feature/local-pr","sha":"abc123"},"labels":[],"state":"open","merged":false}]
JSON
    ;;
  "GET:http://gitea.test/api/v1/repos/example/repo/pulls/7")
    cat <<'JSON'
{"number":7,"title":"Local forge PR","body":"PR body","html_url":"http://gitea.test/example/repo/pulls/7","created_at":"2026-04-14T06:00:00Z","updated_at":"2026-04-14T06:05:00Z","draft":false,"mergeable":true,"state":"open","merged":false,"merged_at":null,"user":{"login":"author-user"},"head":{"ref":"feature/local-pr","sha":"abc123"},"base":{"ref":"main"},"labels":[]}
JSON
    ;;
  "GET:http://gitea.test/api/v1/repos/example/repo/issues/7/comments?page=1&limit=100")
    cat <<'JSON'
[{"body":"PR discussion","created_at":"2026-04-14T06:06:00Z","updated_at":"2026-04-14T06:07:00Z","html_url":"http://gitea.test/example/repo/pulls/7#issuecomment-1"}]
JSON
    ;;
  "POST:http://gitea.test/api/v1/repos/example/repo/pulls")
    jq -e '.title == "Demo PR"' "${data_file}" >/dev/null
    jq -e '.head == "feature/local-pr"' "${data_file}" >/dev/null
    jq -e '.base == "main"' "${data_file}" >/dev/null
    jq -e '.body == "Created from local Gitea PR adapter"' "${data_file}" >/dev/null
    cat <<'JSON'
{"html_url":"http://gitea.test/example/repo/pulls/8"}
JSON
    ;;
  "POST:http://gitea.test/api/v1/repos/example/repo/pulls/7/reviews")
    jq -e '.event == "APPROVED"' "${data_file}" >/dev/null
    jq -e '.body == "LGTM from ACP"' "${data_file}" >/dev/null
    printf '{}\n'
    ;;
  "POST:http://gitea.test/api/v1/repos/example/repo/pulls/7/merge")
    jq -e '.Do == "squash"' "${data_file}" >/dev/null
    jq -e '.delete_branch_after_merge == true' "${data_file}" >/dev/null
    printf '{}\n'
    ;;
  *)
    echo "unexpected curl request: ${method} ${url}" >&2
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
TEST_CURL_LOG="$log_file" \
body_file="$body_file" \
bash <<'EOF'
set -euo pipefail
source "$LIB_PATH"

pr_list_json="$(flow_github_pr_list_json "example/repo" open 100)"
pr_view_json="$(flow_github_pr_view_json "example/repo" 7)"
current_login="$(flow_github_current_login)"
author_login="$(flow_github_pr_author_login "example/repo" 7)"
head_oid="$(flow_github_pr_head_oid "example/repo" 7)"
pr_url="$(flow_github_pr_create "example/repo" "main" "feature/local-pr" "Demo PR" "$body_file")"

jq -e 'length == 1 and .[0].number == 7 and .[0].headRefName == "feature/local-pr"' >/dev/null <<<"$pr_list_json"
jq -e '.number == 7 and .state == "OPEN" and .authorLogin == "author-user" and .headRefOid == "abc123"' >/dev/null <<<"$pr_view_json"
test "$current_login" = "forge-admin"
test "$author_login" = "author-user"
test "$head_oid" = "abc123"
test "$pr_url" = "http://gitea.test/example/repo/pulls/8"

flow_github_pr_review_approve "example/repo" "7" "LGTM from ACP"
flow_github_pr_merge "example/repo" "7" "squash" "yes"
EOF

grep -q 'http://gitea.test/api/v1/repos/example/repo/pulls/7/reviews$' "$log_file"
grep -q 'http://gitea.test/api/v1/repos/example/repo/pulls/7/merge$' "$log_file"

echo "flow gitea pr adapter test passed"
