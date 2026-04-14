#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REAL_CONFIG_LIB="${FLOW_ROOT}/tools/bin/flow-config-lib.sh"
REAL_SHELL_LIB="${FLOW_ROOT}/tools/bin/flow-shell-lib.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

bin_dir="$tmpdir/bin"
body_file="$tmpdir/body.md"
log_file="$tmpdir/curl.log"
mkdir -p "$bin_dir"

cat >"$body_file" <<'EOF'
Created from local Gitea adapter
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
  "GET:http://gitea.test/api/v1/repos/example/repo/issues/1/comments?page=1&limit=100")
    printf '[]\n'
    ;;
  "POST:http://gitea.test/api/v1/repos/example/repo/issues")
    jq -e '.title == "Demo issue"' "${data_file}" >/dev/null
    jq -e '.body == "Created from local Gitea adapter"' "${data_file}" >/dev/null
    cat <<'JSON'
{"html_url":"http://gitea.test/example/repo/issues/2"}
JSON
    ;;
  "POST:http://gitea.test/api/v1/repos/example/repo/issues/1/comments")
    if jq -e '.body == "Queued comment"' "${data_file}" >/dev/null 2>&1; then
      printf '{}\n'
    elif jq -e '.body == "Closing from ACP"' "${data_file}" >/dev/null 2>&1; then
      printf '{}\n'
    else
      echo "unexpected issue comment payload" >&2
      exit 95
    fi
    ;;
  "PATCH:http://gitea.test/api/v1/repos/example/repo/issues/1")
    if jq -e '.body == "Updated body from ACP"' "${data_file}" >/dev/null 2>&1; then
      printf '{}\n'
    elif jq -e '.state == "closed"' "${data_file}" >/dev/null 2>&1; then
      printf '{}\n'
    else
      echo "unexpected patch payload" >&2
      exit 96
    fi
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

issue_url="$(flow_github_issue_create "example/repo" "Demo issue" "$body_file")"
test "$issue_url" = "http://gitea.test/example/repo/issues/2"

flow_github_api_repo "example/repo" "issues/1/comments" --method POST -f body="Queued comment" >/dev/null
flow_github_issue_update_body "example/repo" "1" "Updated body from ACP"
flow_github_issue_close "example/repo" "1" "Closing from ACP"
EOF

grep -q 'http://gitea.test/api/v1/repos/example/repo/issues$' "$log_file"
grep -q 'http://gitea.test/api/v1/repos/example/repo/issues/1/comments$' "$log_file"
grep -q 'http://gitea.test/api/v1/repos/example/repo/issues/1$' "$log_file"

echo "flow gitea issue write adapter test passed"
