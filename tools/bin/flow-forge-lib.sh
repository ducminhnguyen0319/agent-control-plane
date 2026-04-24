flow_git_credential_token_for_repo_slug() {
  local repo_slug="${1:-}"
  local host="${2:-github.com}"
  local path_suffix="${3:-${repo_slug}.git}"
  local credential_payload=""
  local token=""

  [[ -n "${repo_slug}" && -n "${host}" && -n "${path_suffix}" ]] || return 1
  command -v git >/dev/null 2>&1 || return 1

  credential_payload="$(
    printf 'protocol=https\nhost=%s\npath=%s\n\n' "${host}" "${path_suffix}" \
      | git credential fill 2>/dev/null || true
  )"
  token="$(awk -F= '/^password=/{print $2; exit}' <<<"${credential_payload}")"
  [[ -n "${token}" ]] || return 1

  printf '%s\n' "${token}"
}

flow_export_github_cli_auth_env() {
  local repo_slug="${1:-}"
  local token=""

  if flow_using_gitea; then
    return 0
  fi

  if [[ -n "${GH_TOKEN:-}" ]]; then
    return 0
  fi

  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    export GH_TOKEN="${GITHUB_TOKEN}"
    return 0
  fi

  if command -v gh >/dev/null 2>&1; then
    if env -u GH_TOKEN -u GITHUB_TOKEN gh auth status >/dev/null 2>&1 \
      || env -u GH_TOKEN -u GITHUB_TOKEN gh api user --jq .login >/dev/null 2>&1; then
      return 0
    fi
  fi

  token="$(flow_git_credential_token_for_repo_slug "${repo_slug}" || true)"
  if [[ -n "${token}" ]]; then
    export GH_TOKEN="${token}"
    return 0
  fi

  if [[ -n "${GITHUB_PERSONAL_ACCESS_TOKEN:-}" ]]; then
    export GH_TOKEN="${GITHUB_PERSONAL_ACCESS_TOKEN}"
  fi
}

flow_forge_provider() {
  local provider="${ACP_FORGE_PROVIDER:-${F_LOSNING_FORGE_PROVIDER:-github}}"
  provider="$(printf '%s' "${provider}" | tr '[:upper:]' '[:lower:]')"
  case "${provider}" in
    github|gitea)
      printf '%s\n' "${provider}"
      ;;
    *)
      printf 'github\n'
      ;;
  esac
}

flow_using_gitea() {
  [[ "$(flow_forge_provider)" == "gitea" ]]
}

flow_gitea_base_url() {
  local base_url="${ACP_GITEA_BASE_URL:-${GITEA_BASE_URL:-}}"
  [[ -n "${base_url}" ]] || return 1
  printf '%s\n' "${base_url%/}"
}

flow_gitea_base_host() {
  local base_url=""
  base_url="$(flow_gitea_base_url)" || return 1
  base_url="${base_url#http://}"
  base_url="${base_url#https://}"
  printf '%s\n' "${base_url%%/*}"
}

flow_gitea_api_url_for_repo() {
  local repo_slug="${1:?repo slug required}"
  local route="${2:-}"
  local base_url=""

  base_url="$(flow_gitea_base_url)" || return 1
  route="${route#/}"
  if [[ -n "${route}" ]]; then
    printf '%s/api/v1/repos/%s/%s\n' "${base_url}" "${repo_slug}" "${route}"
    return 0
  fi
  printf '%s/api/v1/repos/%s\n' "${base_url}" "${repo_slug}"
}

flow_gitea_auth_curl_args() {
  local repo_slug="${1:-}"
  local credential_token=""

  if [[ -n "${ACP_GITEA_TOKEN:-${GITEA_TOKEN:-}}" ]]; then
    printf -- "-H\0Authorization: token %s\0" "${ACP_GITEA_TOKEN:-${GITEA_TOKEN:-}}"
    return 0
  fi
  if [[ -n "${ACP_GITEA_USERNAME:-${GITEA_USERNAME:-}}" && -n "${ACP_GITEA_PASSWORD:-${GITEA_PASSWORD:-}}" ]]; then
    printf -- "-u\0%s:%s\0" "${ACP_GITEA_USERNAME:-${GITEA_USERNAME:-}}" "${ACP_GITEA_PASSWORD:-${GITEA_PASSWORD:-}}"
    return 0
  fi
  if [[ -n "${repo_slug}" ]]; then
    credential_token="$(flow_git_credential_token_for_repo_slug "${repo_slug}" "$(flow_gitea_base_host)" "${repo_slug}.git" || true)"
    if [[ -n "${credential_token}" ]]; then
      printf -- "-H\0Authorization: token %s\0" "${credential_token}"
      return 0
    fi
  fi
  return 1
}

flow_gitea_api_repo() {
  local repo_slug="${1:?repo slug required}"
  local route="${2:-}"
  local method="GET"
  local paginate="no"
  local slurp="no"
  local jq_filter=""
  local expect_input="no"
  local arg=""
  local url=""
  local input_file=""
  local output=""
  local page="1"
  local per_page="100"
  local response=""
  local body=""
  local link_header=""
  local header_file=""
  local stdout_file=""
  local stderr_file=""
  local curl_status="0"
  local response_status="0"
  local -a curl_args=()
  local -a auth_args=()
  local -a extra_headers=()
  local -a form_fields=()
  local -a pages=()

  shift 2
  while [[ $# -gt 0 ]]; do
    arg="${1:-}"
    case "${arg}" in
      --method)
        method="${2:-GET}"
        shift 2
        ;;
      --paginate)
        paginate="yes"
        shift
        ;;
      --slurp)
        slurp="yes"
        shift
        ;;
      --jq)
        jq_filter="${2:-}"
        shift 2
        ;;
      --input)
        expect_input="yes"
        if [[ "${2:-}" == "-" ]]; then
          input_file="$(mktemp)"
          cat >"${input_file}"
          shift 2
        else
          input_file="${2:-}"
          shift 2
        fi
        ;;
      -f|--field)
        form_fields+=("${2:-}")
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done

  url="$(flow_gitea_api_url_for_repo "${repo_slug}" "${route}")" || {
    rm -f "${input_file}"
    return 1
  }
  while IFS= read -r -d '' arg; do
    auth_args+=("${arg}")
  done < <(flow_gitea_auth_curl_args "${repo_slug}") || true
  if [[ "${#auth_args[@]}" -eq 0 && "${method}" != "GET" ]]; then
    rm -f "${input_file}"
    return 1
  fi

  if [[ "${expect_input}" == "yes" && -n "${input_file}" ]]; then
    extra_headers+=(-H "Content-Type: application/json")
  fi
  if [[ "${#form_fields[@]}" -gt 0 ]]; then
    extra_headers+=(-H "Content-Type: application/json")
    body="$(
      FORM_FIELDS="$(printf '%s\n' "${form_fields[@]}")" python3 - <<'PY'
import json
import os

payload = {}
for line in os.environ.get("FORM_FIELDS", "").splitlines():
    line = line.rstrip("\n")
    if "=" not in line:
        continue
    key, value = line.split("=", 1)
    payload[key] = value
print(json.dumps(payload))
PY
    )"
    input_file="$(mktemp)"
    printf '%s' "${body}" >"${input_file}"
  fi

  if [[ "${paginate}" != "yes" ]]; then
    stdout_file="$(mktemp)"
    stderr_file="$(mktemp)"
    header_file="$(mktemp)"
    curl_args=(-sS -D "${header_file}" -X "${method}")
    if [[ "${#auth_args[@]}" -gt 0 ]]; then
      curl_args+=("${auth_args[@]}")
    fi
    if [[ "${#extra_headers[@]}" -gt 0 ]]; then
      curl_args+=("${extra_headers[@]}")
    fi
    if [[ -n "${input_file}" ]]; then
      curl_args+=(--data-binary "@${input_file}")
    fi
    if curl "${curl_args[@]}" "${url}" >"${stdout_file}" 2>"${stderr_file}"; then
      output="$(cat "${stdout_file}" 2>/dev/null || true)"
      if [[ -n "${jq_filter}" ]]; then
        jq -r "${jq_filter}" <<<"${output}"
      else
        printf '%s' "${output}"
      fi
      rm -f "${input_file}" "${stdout_file}" "${stderr_file}" "${header_file}"
      return 0
    fi
    rm -f "${input_file}" "${stdout_file}" "${stderr_file}" "${header_file}"
    return 1
  fi

  while :; do
    stdout_file="$(mktemp)"
    stderr_file="$(mktemp)"
    header_file="$(mktemp)"
    curl_args=(-sS -D "${header_file}" -X "${method}")
    if [[ "${#auth_args[@]}" -gt 0 ]]; then
      curl_args+=("${auth_args[@]}")
    fi
    if [[ "${#extra_headers[@]}" -gt 0 ]]; then
      curl_args+=("${extra_headers[@]}")
    fi
    if curl "${curl_args[@]}" "${url}$([[ "${url}" == *\?* ]] && printf '&' || printf '?')page=${page}&limit=${per_page}" >"${stdout_file}" 2>"${stderr_file}"; then
      response="$(cat "${stdout_file}" 2>/dev/null || true)"
      pages+=("${response}")
      link_header="$(tr -d '\r' <"${header_file}" | awk 'BEGIN{IGNORECASE=1}/^link:/{sub(/^link:[[:space:]]*/,""); print; exit}')"
      rm -f "${stdout_file}" "${stderr_file}" "${header_file}"
      if [[ "${link_header}" != *'rel="next"'* ]]; then
        break
      fi
      page="$((page + 1))"
    else
      response_status="1"
      rm -f "${stdout_file}" "${stderr_file}" "${header_file}" "${input_file}"
      return "${response_status}"
    fi
  done

  rm -f "${input_file}"
  if [[ "${slurp}" == "yes" ]]; then
    printf '%s\n' "${pages[@]}" | jq -s '.'
    return 0
  fi
  printf '%s' "${pages[0]:-[]}"
}

flow_gitea_issue_view_json() {
  local repo_slug="${1:?repo slug required}"
  local issue_id="${2:?issue id required}"
  local issue_json=""
  local comments_json=""

  issue_json="$(flow_gitea_api_repo "${repo_slug}" "issues/${issue_id}" 2>/dev/null || true)"
  issue_json="$(flow_json_or_default "${issue_json}" '{}')"
  comments_json="$(flow_gitea_api_repo "${repo_slug}" "issues/${issue_id}/comments" --paginate --slurp 2>/dev/null || true)"
  comments_json="$(flow_json_or_default "${comments_json}" '[]')"

  ISSUE_JSON="${issue_json}" COMMENT_PAGES_JSON="${comments_json}" python3 - <<'PY'
import json
import os

issue = json.loads(os.environ.get("ISSUE_JSON", "{}") or "{}")
comment_pages = json.loads(os.environ.get("COMMENT_PAGES_JSON", "[]") or "[]")
comments = []
for page in comment_pages:
    if isinstance(page, list):
        comments.extend(page)
    elif isinstance(page, dict):
        comments.append(page)

result = {
    "number": issue.get("number"),
    "state": str(issue.get("state", "")).upper(),
    "title": issue.get("title") or "",
    "body": issue.get("body") or "",
    "url": issue.get("html_url") or issue.get("url") or "",
    "labels": [{"name": label.get("name", "")} for label in issue.get("labels", []) if isinstance(label, dict)],
    "comments": [
        {
            "body": comment.get("body") or "",
            "createdAt": comment.get("created_at") or "",
            "updatedAt": comment.get("updated_at") or "",
            "url": comment.get("html_url") or "",
        }
        for comment in comments
        if isinstance(comment, dict)
    ],
    "createdAt": issue.get("created_at") or "",
    "updatedAt": issue.get("updated_at") or "",
}

print(json.dumps(result))
PY
}

flow_gitea_issue_list_json() {
  local repo_slug="${1:?repo slug required}"
  local state="${2:-open}"
  local limit="${3:-100}"
  local issues_json=""

  issues_json="$(flow_gitea_api_repo "${repo_slug}" "issues?state=${state}" --paginate --slurp 2>/dev/null || true)"
  issues_json="$(flow_json_or_default "${issues_json}" '[]')"

  ISSUE_PAGES_JSON="${issues_json}" ISSUE_LIMIT="${limit}" python3 - <<'PY'
import json
import os

pages = json.loads(os.environ.get("ISSUE_PAGES_JSON", "[]") or "[]")
limit = int(os.environ.get("ISSUE_LIMIT", "100") or "100")
issues = []

for page in pages:
    if isinstance(page, list):
        issues.extend(page)
    elif isinstance(page, dict):
        issues.append(page)

result = []
for issue in issues:
    if not isinstance(issue, dict):
        continue
    if issue.get("pull_request"):
        continue
    result.append({
        "number": issue.get("number"),
        "createdAt": issue.get("created_at") or "",
        "updatedAt": issue.get("updated_at") or "",
        "title": issue.get("title") or "",
        "url": issue.get("html_url") or issue.get("url") or "",
        "labels": [{"name": label.get("name", "")} for label in issue.get("labels", []) if isinstance(label, dict)],
    })

print(json.dumps(result[:limit]))
PY
}

flow_gitea_pr_view_json() {
  local repo_slug="${1:?repo slug required}"
  local pr_number="${2:?pr number required}"
  local pr_json=""
  local comment_pages_json=""
  local files_json=""
  local reviews_json=""

  pr_json="$(flow_gitea_api_repo "${repo_slug}" "pulls/${pr_number}" 2>/dev/null || true)"
  pr_json="$(flow_json_or_default "${pr_json}" '{}')"
  comment_pages_json="$(flow_gitea_api_repo "${repo_slug}" "issues/${pr_number}/comments" --paginate --slurp 2>/dev/null || true)"
  comment_pages_json="$(flow_json_or_default "${comment_pages_json}" '[]')"
  files_json="$(flow_gitea_api_repo "${repo_slug}" "pulls/${pr_number}/files" --paginate --slurp 2>/dev/null || true)"
  files_json="$(flow_json_or_default "${files_json}" '[]')"
  reviews_json="$(flow_gitea_api_repo "${repo_slug}" "pulls/${pr_number}/reviews" --paginate --slurp 2>/dev/null || true)"
  reviews_json="$(flow_json_or_default "${reviews_json}" '[]')"

  PR_JSON="${pr_json}" COMMENT_PAGES_JSON="${comment_pages_json}" FILES_JSON="${files_json}" REVIEWS_JSON="${reviews_json}" python3 - <<'PY'
import json
import os

pr = json.loads(os.environ.get("PR_JSON", "{}") or "{}")
comment_pages = json.loads(os.environ.get("COMMENT_PAGES_JSON", "[]") or "[]")
file_pages = json.loads(os.environ.get("FILES_JSON", "[]") or "[]")
review_pages = json.loads(os.environ.get("REVIEWS_JSON", "[]") or "[]")
comments = []
for page in comment_pages:
    if isinstance(page, list):
        comments.extend(page)
    elif isinstance(page, dict):
        comments.append(page)

files = []
for page in file_pages:
    if isinstance(page, list):
        files.extend(page)
    elif isinstance(page, dict):
        files.append(page)

reviews = []
for page in review_pages:
    if isinstance(page, list):
        reviews.extend(page)
    elif isinstance(page, dict):
        reviews.append(page)

pr_state = str(pr.get("state", "")).upper()
if pr.get("merged") or pr.get("merged_at"):
    pr_state = "MERGED"

review_states = [
    str(review.get("state") or "").upper()
    for review in reviews
    if isinstance(review, dict)
]
review_decision = ""
if any(state == "APPROVED" for state in review_states):
    review_decision = "APPROVED"
elif any(state in {"CHANGES_REQUESTED", "REQUEST_CHANGES"} for state in review_states):
    review_decision = "CHANGES_REQUESTED"

result = {
    "number": pr.get("number"),
    "title": pr.get("title") or "",
    "body": pr.get("body") or "",
    "url": pr.get("html_url") or pr.get("url") or "",
    "headRefName": ((pr.get("head") or {}).get("ref")) or "",
    "headRefOid": ((pr.get("head") or {}).get("sha")) or "",
    "baseRefName": ((pr.get("base") or {}).get("ref")) or "",
    "mergeStateStatus": "CLEAN" if pr.get("mergeable") else "UNKNOWN",
    "statusCheckRollup": [],
    "labels": [{"name": label.get("name", "")} for label in pr.get("labels", []) if isinstance(label, dict)],
    "comments": [
        {
            "body": comment.get("body") or "",
            "createdAt": comment.get("created_at") or "",
            "updatedAt": comment.get("updated_at") or "",
            "url": comment.get("html_url") or "",
        }
        for comment in comments
        if isinstance(comment, dict)
    ],
    "state": pr_state,
    "isDraft": bool(pr.get("draft")),
    "createdAt": pr.get("created_at") or "",
    "updatedAt": pr.get("updated_at") or "",
    "mergedAt": pr.get("merged_at") or "",
    "authorLogin": ((pr.get("user") or {}).get("login")) or "",
    "files": [
        {"path": file.get("filename") or ""}
        for file in files
        if isinstance(file, dict) and (file.get("filename") or "")
    ],
    "reviewRequests": [
        {"login": reviewer.get("login") or ""}
        for reviewer in (pr.get("requested_reviewers") or [])
        if isinstance(reviewer, dict)
    ],
    "reviewDecision": review_decision,
}

print(json.dumps(result))
PY
}

flow_gitea_pr_list_json() {
  local repo_slug="${1:?repo slug required}"
  local state="${2:-open}"
  local limit="${3:-100}"
  local pulls_state="${state}"
  local pr_pages_json=""

  if [[ "${state}" == "merged" ]]; then
    pulls_state="closed"
  fi

  pr_pages_json="$(flow_gitea_api_repo "${repo_slug}" "pulls?state=${pulls_state}" --paginate --slurp 2>/dev/null || true)"
  pr_pages_json="$(flow_json_or_default "${pr_pages_json}" '[]')"

  PR_PAGES_JSON="${pr_pages_json}" PR_LIMIT="${limit}" PR_STATE_FILTER="${state}" python3 - <<'PY'
import json
import os

pages = json.loads(os.environ.get("PR_PAGES_JSON", "[]") or "[]")
limit = int(os.environ.get("PR_LIMIT", "100") or "100")
state_filter = os.environ.get("PR_STATE_FILTER", "open")
prs = []
for page in pages:
    if isinstance(page, list):
        prs.extend(page)
    elif isinstance(page, dict):
        prs.append(page)

result = []
for pr in prs:
    if not isinstance(pr, dict):
        continue
    merged = bool(pr.get("merged") or pr.get("merged_at"))
    state = str(pr.get("state", "")).lower()
    if state_filter == "open" and state != "open":
        continue
    if state_filter == "closed" and state != "closed":
        continue
    if state_filter == "merged" and not merged:
        continue
    normalized_state = "MERGED" if merged else state.upper()
    result.append({
        "number": pr.get("number"),
        "title": pr.get("title") or "",
        "body": pr.get("body") or "",
        "url": pr.get("html_url") or pr.get("url") or "",
        "headRefName": ((pr.get("head") or {}).get("ref")) or "",
        "headRefOid": ((pr.get("head") or {}).get("sha")) or "",
        "baseRefName": ((pr.get("base") or {}).get("ref")) or "",
        "createdAt": pr.get("created_at") or "",
        "mergedAt": pr.get("merged_at") or "",
        "state": normalized_state,
        "isDraft": bool(pr.get("draft")),
        "labels": [{"name": label.get("name", "")} for label in pr.get("labels", []) if isinstance(label, dict)],
        "comments": [],
        "authorLogin": ((pr.get("user") or {}).get("login")) or "",
    })
    if len(result) >= limit:
        break

print(json.dumps(result))
PY
}

flow_github_output_indicates_rate_limit() {
  grep -Eiq 'API rate limit exceeded|secondary rate limit|rate limit exceeded|HTTP 403' <<<"${1:-}"
}

flow_github_core_rate_limit_state_bin() {
  local flow_root=""
  local candidate=""

  flow_root="$(resolve_flow_skill_dir "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")" || return 1
  candidate="${flow_root}/tools/bin/github-core-rate-limit-state.sh"
  [[ -x "${candidate}" ]] || return 1
  printf '%s\n' "${candidate}"
}

flow_github_core_rate_limit_state_output() {
  local state_bin=""

  state_bin="$(flow_github_core_rate_limit_state_bin)" || return 1
  "${state_bin}" get 2>/dev/null || true
}

flow_github_core_rate_limit_active() {
  local state_out=""
  local ready=""

  state_out="$(flow_github_core_rate_limit_state_output)" || return 1
  ready="$(awk -F= '/^READY=/{print $2; exit}' <<<"${state_out}")"
  [[ "${ready}" == "no" ]]
}

flow_github_core_rate_limit_schedule() {
  local reason="${1:-github-api-rate-limit}"
  local reset_epoch="${2:-}"
  local state_bin=""
  local now_epoch=""

  state_bin="$(flow_github_core_rate_limit_state_bin)" || return 0
  now_epoch="$(date +%s)"
  if [[ "${reset_epoch}" =~ ^[0-9]+$ ]] && (( reset_epoch > now_epoch )); then
    "${state_bin}" schedule "${reason}" --next-at-epoch "${reset_epoch}" >/dev/null 2>&1 || true
    return 0
  fi

  "${state_bin}" schedule "${reason}" >/dev/null 2>&1 || true
}

flow_github_core_rate_limit_clear() {
  local state_bin=""

  state_bin="$(flow_github_core_rate_limit_state_bin)" || return 0
  "${state_bin}" clear >/dev/null 2>&1 || true
}

flow_github_graphql_available() {
  local repo_slug="${1:-}"
  local rate_limit_json=""
  local graphql_remaining=""
  local core_remaining=""
  local core_reset=""
  local stderr_file=""
  local stderr_output=""

  if [[ "${FLOW_GITHUB_GRAPHQL_AVAILABLE_CACHE:-}" == "yes" ]]; then
    return 0
  fi
  if [[ "${FLOW_GITHUB_GRAPHQL_AVAILABLE_CACHE:-}" == "no" ]]; then
    return 1
  fi

  if flow_github_core_rate_limit_active; then
    FLOW_GITHUB_GRAPHQL_AVAILABLE_CACHE="no"
    return 1
  fi

  flow_export_github_cli_auth_env "${repo_slug}"
  stderr_file="$(mktemp)"
  if rate_limit_json="$(gh api rate_limit 2>"${stderr_file}")"; then
    graphql_remaining="$(jq -r '.resources.graphql.remaining // empty' <<<"${rate_limit_json}" 2>/dev/null || true)"
    core_remaining="$(jq -r '.resources.core.remaining // empty' <<<"${rate_limit_json}" 2>/dev/null || true)"
    core_reset="$(jq -r '.resources.core.reset // empty' <<<"${rate_limit_json}" 2>/dev/null || true)"
    if [[ "${core_remaining}" =~ ^[0-9]+$ ]]; then
      if (( core_remaining > 0 )); then
        flow_github_core_rate_limit_clear
      else
        flow_github_core_rate_limit_schedule "github-api-rate-limit" "${core_reset}"
        FLOW_GITHUB_GRAPHQL_AVAILABLE_CACHE="no"
        rm -f "${stderr_file}"
        return 1
      fi
    fi
  else
    stderr_output="$(cat "${stderr_file}" 2>/dev/null || true)"
    if flow_github_output_indicates_rate_limit "${stderr_output}"; then
      flow_github_core_rate_limit_schedule "github-api-rate-limit"
    fi
    FLOW_GITHUB_GRAPHQL_AVAILABLE_CACHE="no"
    rm -f "${stderr_file}"
    return 1
  fi
  rm -f "${stderr_file}"

  if [[ "${graphql_remaining}" =~ ^[0-9]+$ ]] && (( graphql_remaining > 0 )); then
    FLOW_GITHUB_GRAPHQL_AVAILABLE_CACHE="yes"
    return 0
  fi

  FLOW_GITHUB_GRAPHQL_AVAILABLE_CACHE="no"
  return 1
}

flow_github_repo_id_cache_var() {
  local repo_slug="${1:-}"
  local sanitized="${repo_slug//[^A-Za-z0-9]/_}"
  printf 'FLOW_GITHUB_REPO_ID_CACHE_%s\n' "${sanitized}"
}

flow_github_repo_id_for_repo_slug() {
  local repo_slug="${1:-}"
  local cache_var=""
  local cached_value=""
  local repos_pages_json=""
  local repo_id=""
  local stderr_file=""
  local stderr_output=""

  [[ -n "${repo_slug}" ]] || return 1
  command -v gh >/dev/null 2>&1 || return 1

  cache_var="$(flow_github_repo_id_cache_var "${repo_slug}")"
  cached_value="${!cache_var:-}"
  if [[ -n "${cached_value}" ]]; then
    printf '%s\n' "${cached_value}"
    return 0
  fi

  repo_id="$(flow_explicit_github_repo_id "${repo_slug}" || true)"
  if [[ -n "${repo_id}" ]]; then
    printf -v "${cache_var}" '%s' "${repo_id}"
    printf '%s\n' "${repo_id}"
    return 0
  fi

  if flow_github_core_rate_limit_active; then
    return 1
  fi

  flow_export_github_cli_auth_env "${repo_slug}"
  stderr_file="$(mktemp)"
  if repos_pages_json="$(
    gh api 'user/repos?per_page=100&visibility=all&affiliation=owner,collaborator,organization_member' \
      --paginate \
      --slurp 2>"${stderr_file}" || true
  )" && [[ -n "${repos_pages_json}" ]]; then
    flow_github_core_rate_limit_clear
  else
    stderr_output="$(cat "${stderr_file}" 2>/dev/null || true)"
    if flow_github_output_indicates_rate_limit "${stderr_output}"; then
      flow_github_core_rate_limit_schedule "github-api-rate-limit"
    fi
  fi
  rm -f "${stderr_file}"
  [[ -n "${repos_pages_json}" ]] || return 1

  repo_id="$(
    REPOS_PAGES_JSON="${repos_pages_json}" TARGET_REPO_SLUG="${repo_slug}" python3 - <<'PY'
import json
import os
import sys

pages = json.loads(os.environ.get("REPOS_PAGES_JSON", "[]") or "[]")
target = os.environ.get("TARGET_REPO_SLUG", "")

for page in pages:
    if isinstance(page, list):
        for repo in page:
            if isinstance(repo, dict) and repo.get("full_name") == target:
                value = repo.get("id")
                if value is not None:
                    print(value)
                    sys.exit(0)
    elif isinstance(page, dict) and page.get("full_name") == target:
        value = page.get("id")
        if value is not None:
            print(value)
            sys.exit(0)
PY
  )"
  [[ -n "${repo_id}" ]] || return 1

  printf -v "${cache_var}" '%s' "${repo_id}"
  printf '%s\n' "${repo_id}"
}

flow_github_repo_api_prefix() {
  local repo_slug="${1:-}"
  local repo_id=""

  repo_id="$(flow_github_repo_id_for_repo_slug "${repo_slug}")" || return 1
  printf 'repositories/%s\n' "${repo_id}"
}

flow_github_api_repo() {
  local repo_slug="${1:?repo slug required}"
  local route="${2:-}"
  local repo_prefix=""
  local direct_route="repos/${repo_slug}"
  local fallback_route=""
  local output=""
  local stdin_file=""
  local request_status=0
  local expect_input_value="false"
  local arg=""
  local index=0
  local gh_arg_count=0
  local stdout_file=""
  local stderr_file=""
  local error_output=""
  local -a gh_args=()

  if flow_using_gitea; then
    flow_gitea_api_repo "$@"
    return $?
  fi

  route="${route#/}"
  if [[ -n "${route}" ]]; then
    direct_route="${direct_route}/${route}"
  fi

  if [[ $# -gt 2 ]]; then
    gh_args=("${@:3}")
    gh_arg_count="${#gh_args[@]}"
  fi
  for ((index = 0; index < ${#gh_args[@]}; index++)); do
    arg="${gh_args[${index}]}"
    if [[ "${expect_input_value}" == "true" ]]; then
      if [[ "${arg}" == "-" ]]; then
        if [[ -z "${stdin_file}" ]]; then
          stdin_file="$(mktemp)"
          cat >"${stdin_file}"
        fi
        gh_args[${index}]="${stdin_file}"
      fi
      expect_input_value="false"
    elif [[ "${arg}" == "--input" ]]; then
      expect_input_value="true"
    fi
  done

  if flow_github_core_rate_limit_active; then
    rm -f "${stdin_file}"
    return 1
  fi

  flow_export_github_cli_auth_env "${repo_slug}"
  stdout_file="$(mktemp)"
  stderr_file="$(mktemp)"
  if [[ "${gh_arg_count}" -gt 0 ]]; then
    if gh api "${direct_route}" "${gh_args[@]}" >"${stdout_file}" 2>"${stderr_file}"; then
      output="$(cat "${stdout_file}" 2>/dev/null || true)"
      flow_github_core_rate_limit_clear
      printf '%s' "${output}"
      rm -f "${stdin_file}" "${stdout_file}" "${stderr_file}"
      return 0
    fi
  else
    if gh api "${direct_route}" >"${stdout_file}" 2>"${stderr_file}"; then
      output="$(cat "${stdout_file}" 2>/dev/null || true)"
      flow_github_core_rate_limit_clear
      printf '%s' "${output}"
      rm -f "${stdin_file}" "${stdout_file}" "${stderr_file}"
      return 0
    fi
  fi
  error_output="$(cat "${stderr_file}" 2>/dev/null || true)"
  if flow_github_output_indicates_rate_limit "${error_output}"; then
    flow_github_core_rate_limit_schedule "github-api-rate-limit"
    rm -f "${stdin_file}" "${stdout_file}" "${stderr_file}"
    return 1
  fi

  if ! repo_prefix="$(flow_github_repo_api_prefix "${repo_slug}")"; then
    rm -f "${stdin_file}" "${stdout_file}" "${stderr_file}"
    return 1
  fi
  fallback_route="${repo_prefix}"
  if [[ -n "${route}" ]]; then
    fallback_route="${fallback_route}/${route}"
  fi
  if [[ "${gh_arg_count}" -gt 0 ]]; then
    if gh api "${fallback_route}" "${gh_args[@]}" >"${stdout_file}" 2>"${stderr_file}"; then
      output="$(cat "${stdout_file}" 2>/dev/null || true)"
      flow_github_core_rate_limit_clear
      printf '%s' "${output}"
      rm -f "${stdin_file}" "${stdout_file}" "${stderr_file}"
      return 0
    else
      request_status=$?
    fi
  else
    if gh api "${fallback_route}" >"${stdout_file}" 2>"${stderr_file}"; then
      output="$(cat "${stdout_file}" 2>/dev/null || true)"
      flow_github_core_rate_limit_clear
      printf '%s' "${output}"
      rm -f "${stdin_file}" "${stdout_file}" "${stderr_file}"
      return 0
    else
      request_status=$?
    fi
  fi
  error_output="$(cat "${stderr_file}" 2>/dev/null || true)"
  if flow_github_output_indicates_rate_limit "${error_output}"; then
    flow_github_core_rate_limit_schedule "github-api-rate-limit"
  fi
  rm -f "${stdin_file}" "${stdout_file}" "${stderr_file}"
  return "${request_status}"
}

flow_json_or_default() {
  local raw_value="${1-}"
  local default_value="${2:-null}"

  if [[ -z "${raw_value}" ]]; then
    printf '%s\n' "${default_value}"
    return 0
  fi

  if jq -e . >/dev/null 2>&1 <<<"${raw_value}"; then
    printf '%s\n' "${raw_value}"
  else
    printf '%s\n' "${default_value}"
  fi
}

flow_github_urlencode() {
  local raw_value="${1:-}"

  RAW_VALUE="${raw_value}" python3 - <<'PY'
import os
from urllib.parse import quote

print(quote(os.environ.get("RAW_VALUE", ""), safe=""))
PY
}

flow_github_issue_view_json_live() {
  local repo_slug="${1:?repo slug required}"
  local issue_id="${2:?issue id required}"
  local issue_json=""
  local comment_pages_json=""

  if flow_using_gitea; then
    flow_gitea_issue_view_json "${repo_slug}" "${issue_id}"
    return $?
  fi

  if flow_github_graphql_available "${repo_slug}" \
    && issue_json="$(gh issue view "${issue_id}" -R "${repo_slug}" --json number,state,title,body,url,labels,comments,createdAt,updatedAt 2>/dev/null)"; then
    printf '%s\n' "${issue_json}"
    return 0
  fi

  if ! issue_json="$(flow_github_api_repo "${repo_slug}" "issues/${issue_id}" 2>/dev/null)"; then
    return 1
  fi
  issue_json="$(flow_json_or_default "${issue_json}" '{}')"
  if ! comment_pages_json="$(flow_github_api_repo "${repo_slug}" "issues/${issue_id}/comments?per_page=100" --paginate --slurp 2>/dev/null)"; then
    return 1
  fi
  comment_pages_json="$(flow_json_or_default "${comment_pages_json}" '[]')"

  ISSUE_JSON="${issue_json}" COMMENT_PAGES_JSON="${comment_pages_json}" python3 - <<'PY'
import json
import os

issue = json.loads(os.environ.get("ISSUE_JSON", "{}") or "{}")
comment_pages = json.loads(os.environ.get("COMMENT_PAGES_JSON", "[]") or "[]")
comments = []
for page in comment_pages:
    if isinstance(page, list):
        comments.extend(page)
    elif isinstance(page, dict):
        comments.append(page)

result = {
    "number": issue.get("number"),
    "state": str(issue.get("state", "")).upper(),
    "title": issue.get("title") or "",
    "body": issue.get("body") or "",
    "url": issue.get("html_url") or issue.get("url") or "",
    "labels": [{"name": label.get("name", "")} for label in issue.get("labels", []) if isinstance(label, dict)],
    "comments": [
        {
            "body": comment.get("body") or "",
            "createdAt": comment.get("created_at") or "",
            "updatedAt": comment.get("updated_at") or "",
            "url": comment.get("html_url") or "",
        }
        for comment in comments
        if isinstance(comment, dict)
    ],
    "createdAt": issue.get("created_at") or "",
    "updatedAt": issue.get("updated_at") or "",
}

print(json.dumps(result))
PY
}

flow_github_issue_view_json() {
  local repo_slug="${1:?repo slug required}"
  local issue_id="${2:?issue id required}"
  local issue_json=""
  local comment_pages_json=""

  if flow_using_gitea; then
    flow_gitea_issue_view_json "${repo_slug}" "${issue_id}"
    return $?
  fi

  if flow_github_graphql_available "${repo_slug}" \
    && issue_json="$(gh issue view "${issue_id}" -R "${repo_slug}" --json number,state,title,body,url,labels,comments,createdAt,updatedAt 2>/dev/null)"; then
    printf '%s\n' "${issue_json}"
    return 0
  fi

  issue_json="$(flow_github_api_repo "${repo_slug}" "issues/${issue_id}" 2>/dev/null || true)"
  issue_json="$(flow_json_or_default "${issue_json}" '{}')"
  comment_pages_json="$(flow_github_api_repo "${repo_slug}" "issues/${issue_id}/comments?per_page=100" --paginate --slurp 2>/dev/null || true)"
  comment_pages_json="$(flow_json_or_default "${comment_pages_json}" '[]')"

  ISSUE_JSON="${issue_json}" COMMENT_PAGES_JSON="${comment_pages_json}" python3 - <<'PY'
import json
import os

issue = json.loads(os.environ.get("ISSUE_JSON", "{}") or "{}")
comment_pages = json.loads(os.environ.get("COMMENT_PAGES_JSON", "[]") or "[]")
comments = []
for page in comment_pages:
    if isinstance(page, list):
        comments.extend(page)
    elif isinstance(page, dict):
        comments.append(page)

result = {
    "number": issue.get("number"),
    "state": str(issue.get("state", "")).upper(),
    "title": issue.get("title") or "",
    "body": issue.get("body") or "",
    "url": issue.get("html_url") or issue.get("url") or "",
    "labels": [{"name": label.get("name", "")} for label in issue.get("labels", []) if isinstance(label, dict)],
    "comments": [
        {
            "body": comment.get("body") or "",
            "createdAt": comment.get("created_at") or "",
            "updatedAt": comment.get("updated_at") or "",
            "url": comment.get("html_url") or "",
        }
        for comment in comments
        if isinstance(comment, dict)
    ],
    "createdAt": issue.get("created_at") or "",
    "updatedAt": issue.get("updated_at") or "",
}

print(json.dumps(result))
PY
}

flow_github_issue_list_json_live() {
  local repo_slug="${1:?repo slug required}"
  local state="${2:-open}"
  local limit="${3:-100}"
  local issues_json=""
  local per_page="100"

  if flow_using_gitea; then
    flow_gitea_issue_list_json "${repo_slug}" "${state}" "${limit}"
    return $?
  fi

  if flow_github_graphql_available "${repo_slug}" \
    && issues_json="$(gh issue list -R "${repo_slug}" --state "${state}" --limit "${limit}" --json number,createdAt,updatedAt,title,url,labels 2>/dev/null)"; then
    printf '%s\n' "${issues_json}"
    return 0
  fi

  if [[ "${limit}" =~ ^[0-9]+$ ]] && (( limit > 0 && limit < 100 )); then
    per_page="${limit}"
  fi

  if ! issues_json="$(flow_github_api_repo "${repo_slug}" "issues?state=${state}&per_page=${per_page}" --paginate --slurp 2>/dev/null)"; then
    return 1
  fi
  issues_json="$(flow_json_or_default "${issues_json}" '[]')"

  ISSUE_PAGES_JSON="${issues_json}" ISSUE_LIMIT="${limit}" python3 - <<'PY'
import json
import os

pages = json.loads(os.environ.get("ISSUE_PAGES_JSON", "[]") or "[]")
limit = int(os.environ.get("ISSUE_LIMIT", "100") or "100")
issues = []

for page in pages:
    if isinstance(page, list):
        issues.extend(page)
    elif isinstance(page, dict):
        issues.append(page)

result = []
for issue in issues:
    if not isinstance(issue, dict):
        continue
    if issue.get("pull_request"):
        continue
    result.append({
        "number": issue.get("number"),
        "createdAt": issue.get("created_at") or "",
        "updatedAt": issue.get("updated_at") or "",
        "title": issue.get("title") or "",
        "url": issue.get("html_url") or issue.get("url") or "",
        "labels": [{"name": label.get("name", "")} for label in issue.get("labels", []) if isinstance(label, dict)],
    })

print(json.dumps(result[:limit]))
PY
}

flow_github_issue_list_json() {
  local repo_slug="${1:?repo slug required}"
  local state="${2:-open}"
  local limit="${3:-100}"
  local issues_json=""
  local per_page="100"

  if flow_using_gitea; then
    flow_gitea_issue_list_json "${repo_slug}" "${state}" "${limit}"
    return $?
  fi

  if flow_github_graphql_available "${repo_slug}" \
    && issues_json="$(gh issue list -R "${repo_slug}" --state "${state}" --limit "${limit}" --json number,createdAt,updatedAt,title,url,labels 2>/dev/null)"; then
    printf '%s\n' "${issues_json}"
    return 0
  fi

  if [[ "${limit}" =~ ^[0-9]+$ ]] && (( limit > 0 && limit < 100 )); then
    per_page="${limit}"
  fi

  issues_json="$(flow_github_api_repo "${repo_slug}" "issues?state=${state}&per_page=${per_page}" --paginate --slurp 2>/dev/null || true)"
  issues_json="$(flow_json_or_default "${issues_json}" '[]')"

  ISSUE_PAGES_JSON="${issues_json}" ISSUE_LIMIT="${limit}" python3 - <<'PY'
import json
import os

pages = json.loads(os.environ.get("ISSUE_PAGES_JSON", "[]") or "[]")
limit = int(os.environ.get("ISSUE_LIMIT", "100") or "100")
issues = []

for page in pages:
    if isinstance(page, list):
        issues.extend(page)
    elif isinstance(page, dict):
        issues.append(page)

result = []
for issue in issues:
    if not isinstance(issue, dict):
        continue
    if issue.get("pull_request"):
        continue
    result.append({
        "number": issue.get("number"),
        "createdAt": issue.get("created_at") or "",
        "updatedAt": issue.get("updated_at") or "",
        "title": issue.get("title") or "",
        "url": issue.get("html_url") or issue.get("url") or "",
        "labels": [{"name": label.get("name", "")} for label in issue.get("labels", []) if isinstance(label, dict)],
    })

print(json.dumps(result[:limit]))
PY
}

flow_github_pr_view_json() {
  local repo_slug="${1:?repo slug required}"
  local pr_number="${2:?pr number required}"
  local pr_json=""
  local issue_json=""
  local comment_pages_json=""
  local head_sha=""
  local check_runs_json="{}"
  local status_json="{}"

  if flow_using_gitea; then
    flow_gitea_pr_view_json "${repo_slug}" "${pr_number}"
    return $?
  fi

  if flow_github_graphql_available "${repo_slug}" \
    && pr_json="$(gh pr view "${pr_number}" -R "${repo_slug}" --json number,title,body,url,headRefName,baseRefName,mergeStateStatus,statusCheckRollup,labels,comments,state,isDraft 2>/dev/null)"; then
    printf '%s\n' "${pr_json}"
    return 0
  fi

  pr_json="$(flow_github_api_repo "${repo_slug}" "pulls/${pr_number}" 2>/dev/null || true)"
  pr_json="$(flow_json_or_default "${pr_json}" '{}')"
  issue_json="$(flow_github_api_repo "${repo_slug}" "issues/${pr_number}" 2>/dev/null || true)"
  issue_json="$(flow_json_or_default "${issue_json}" '{}')"
  comment_pages_json="$(flow_github_api_repo "${repo_slug}" "issues/${pr_number}/comments?per_page=100" --paginate --slurp 2>/dev/null || true)"
  comment_pages_json="$(flow_json_or_default "${comment_pages_json}" '[]')"
  head_sha="$(
    PR_JSON="${pr_json}" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ.get("PR_JSON", "{}") or "{}")
head = payload.get("head") or {}
print(head.get("sha") or "")
PY
  )"
  if [[ -n "${head_sha}" ]]; then
    check_runs_json="$(flow_github_api_repo "${repo_slug}" "commits/${head_sha}/check-runs?per_page=100" 2>/dev/null || true)"
    check_runs_json="$(flow_json_or_default "${check_runs_json}" '{}')"
    status_json="$(flow_github_api_repo "${repo_slug}" "commits/${head_sha}/status" 2>/dev/null || true)"
    status_json="$(flow_json_or_default "${status_json}" '{}')"
  fi

  PR_JSON="${pr_json}" ISSUE_JSON="${issue_json}" COMMENT_PAGES_JSON="${comment_pages_json}" CHECK_RUNS_JSON="${check_runs_json}" STATUS_JSON="${status_json}" python3 - <<'PY'
import json
import os

pr = json.loads(os.environ.get("PR_JSON", "{}") or "{}")
issue = json.loads(os.environ.get("ISSUE_JSON", "{}") or "{}")
comment_pages = json.loads(os.environ.get("COMMENT_PAGES_JSON", "[]") or "[]")
check_runs_payload = json.loads(os.environ.get("CHECK_RUNS_JSON", "{}") or "{}")
status_payload = json.loads(os.environ.get("STATUS_JSON", "{}") or "{}")

comments = []
for page in comment_pages:
    if isinstance(page, list):
        comments.extend(page)
    elif isinstance(page, dict):
        comments.append(page)

status_check_rollup = []
for run in check_runs_payload.get("check_runs", []) or []:
    if not isinstance(run, dict):
        continue
    status_check_rollup.append({
        "name": run.get("name") or "",
        "status": run.get("status") or "",
        "conclusion": run.get("conclusion") or "",
    })
for item in status_payload.get("statuses", []) or []:
    if not isinstance(item, dict):
        continue
    state = item.get("state") or ""
    status_check_rollup.append({
        "context": item.get("context") or "",
        "status": state,
        "conclusion": state,
    })

pr_state = str(pr.get("state", "")).upper()
if pr.get("merged_at"):
    pr_state = "MERGED"

result = {
    "number": pr.get("number"),
    "title": pr.get("title") or "",
    "body": pr.get("body") or issue.get("body") or "",
    "url": pr.get("html_url") or pr.get("url") or "",
    "headRefName": ((pr.get("head") or {}).get("ref")) or "",
    "headRefOid": ((pr.get("head") or {}).get("sha")) or "",
    "baseRefName": ((pr.get("base") or {}).get("ref")) or "",
    "mergeStateStatus": str(pr.get("mergeable_state") or "UNKNOWN").upper(),
    "statusCheckRollup": status_check_rollup,
    "labels": [{"name": label.get("name", "")} for label in issue.get("labels", []) if isinstance(label, dict)],
    "comments": [
        {
            "body": comment.get("body") or "",
            "createdAt": comment.get("created_at") or "",
            "updatedAt": comment.get("updated_at") or "",
            "url": comment.get("html_url") or "",
        }
        for comment in comments
        if isinstance(comment, dict)
    ],
    "state": pr_state,
    "isDraft": bool(pr.get("draft")),
    "createdAt": pr.get("created_at") or "",
    "updatedAt": pr.get("updated_at") or "",
    "mergedAt": pr.get("merged_at") or "",
    "authorLogin": ((pr.get("user") or {}).get("login")) or "",
}

print(json.dumps(result))
PY
}

flow_github_pr_list_json_live() {
  local repo_slug="${1:?repo slug required}"
  local state="${2:-open}"
  local limit="${3:-100}"
  local pr_json=""
  local per_page="100"
  local pulls_state="${state}"
  local pull_pages_json=""
  local selected_prs_json=""
  local item_jsonl_file=""
  local current_pr_json=""
  local issue_json=""
  local comment_pages_json=""
  local pr_number=""

  if flow_using_gitea; then
    flow_gitea_pr_list_json "${repo_slug}" "${state}" "${limit}"
    return $?
  fi

  if flow_github_graphql_available "${repo_slug}" \
    && pr_json="$(gh pr list -R "${repo_slug}" --state "${state}" --limit "${limit}" --json number,title,body,url,headRefName,labels,comments,createdAt,mergedAt,isDraft 2>/dev/null)"; then
    printf '%s\n' "${pr_json}"
    return 0
  fi

  if [[ "${state}" == "merged" ]]; then
    pulls_state="closed"
  fi
  if [[ "${limit}" =~ ^[0-9]+$ ]] && (( limit > 0 && limit < 100 )); then
    per_page="${limit}"
  fi

  if ! pull_pages_json="$(flow_github_api_repo "${repo_slug}" "pulls?state=${pulls_state}&per_page=${per_page}" --paginate --slurp 2>/dev/null)"; then
    return 1
  fi
  pull_pages_json="$(flow_json_or_default "${pull_pages_json}" '[]')"

  if ! selected_prs_json="$(
    PULL_PAGES_JSON="${pull_pages_json}" PR_LIMIT="${limit}" PR_STATE_FILTER="${state}" python3 - <<'PY'
import json
import os

pages = json.loads(os.environ.get("PULL_PAGES_JSON", "[]") or "[]")
limit = int(os.environ.get("PR_LIMIT", "100") or "100")
state_filter = os.environ.get("PR_STATE_FILTER", "open")
pulls = []

for page in pages:
    if isinstance(page, list):
        pulls.extend(page)
    elif isinstance(page, dict):
        pulls.append(page)

result = []
for pr in pulls:
    if not isinstance(pr, dict):
        continue
    if state_filter == "merged" and not pr.get("merged_at"):
        continue
    result.append({
        "number": pr.get("number"),
        "title": pr.get("title") or "",
        "body": pr.get("body") or "",
        "url": pr.get("html_url") or pr.get("url") or "",
        "headRefName": ((pr.get("head") or {}).get("ref")) or "",
        "createdAt": pr.get("created_at") or "",
        "mergedAt": pr.get("merged_at") or "",
        "isDraft": bool(pr.get("draft")),
    })
    if len(result) >= limit:
        break

print(json.dumps(result))
PY
  )"; then
    return 1
  fi

  item_jsonl_file="$(mktemp)"

  while IFS= read -r current_pr_json; do
    [[ -n "${current_pr_json}" ]] || continue
    pr_number="$(jq -r '.number // ""' <<<"${current_pr_json}")"
    [[ -n "${pr_number}" ]] || continue
    if ! issue_json="$(flow_github_api_repo "${repo_slug}" "issues/${pr_number}" 2>/dev/null)"; then
      rm -f "${item_jsonl_file}"
      return 1
    fi
    issue_json="$(flow_json_or_default "${issue_json}" '{}')"
    if ! comment_pages_json="$(flow_github_api_repo "${repo_slug}" "issues/${pr_number}/comments?per_page=100" --paginate --slurp 2>/dev/null)"; then
      rm -f "${item_jsonl_file}"
      return 1
    fi
    comment_pages_json="$(flow_json_or_default "${comment_pages_json}" '[]')"
    PR_JSON="${current_pr_json}" ISSUE_JSON="${issue_json}" COMMENT_PAGES_JSON="${comment_pages_json}" python3 - <<'PY' >>"${item_jsonl_file}"
import json
import os

pr = json.loads(os.environ.get("PR_JSON", "{}") or "{}")
issue = json.loads(os.environ.get("ISSUE_JSON", "{}") or "{}")
comment_pages = json.loads(os.environ.get("COMMENT_PAGES_JSON", "[]") or "[]")
comments = []
for page in comment_pages:
    if isinstance(page, list):
        comments.extend(page)
    elif isinstance(page, dict):
        comments.append(page)

result = {
    "number": pr.get("number"),
    "title": pr.get("title") or "",
    "body": pr.get("body") or issue.get("body") or "",
    "url": pr.get("url") or issue.get("html_url") or issue.get("url") or "",
    "headRefName": pr.get("headRefName") or "",
    "createdAt": pr.get("createdAt") or "",
    "mergedAt": pr.get("mergedAt") or "",
    "isDraft": bool(pr.get("isDraft")),
    "labels": [{"name": label.get("name", "")} for label in issue.get("labels", []) if isinstance(label, dict)],
    "comments": [
        {
            "body": comment.get("body") or "",
            "createdAt": comment.get("created_at") or "",
            "updatedAt": comment.get("updated_at") or "",
            "url": comment.get("html_url") or "",
        }
        for comment in comments
        if isinstance(comment, dict)
    ],
}

print(json.dumps(result))
PY
  done < <(jq -c '.[]' <<<"${selected_prs_json}" 2>/dev/null || true)

  if ! jq -s '.' "${item_jsonl_file}" 2>/dev/null; then
    rm -f "${item_jsonl_file}"
    return 1
  fi

  rm -f "${item_jsonl_file}"
}

flow_github_pr_list_json() {
  local repo_slug="${1:?repo slug required}"
  local state="${2:-open}"
  local limit="${3:-100}"
  local pr_json=""
  local per_page="100"
  local pulls_state="${state}"
  local pull_pages_json=""
  local selected_prs_json=""
  local item_jsonl_file=""
  local current_pr_json=""
  local issue_json=""
  local comment_pages_json=""
  local pr_number=""

  if flow_using_gitea; then
    flow_gitea_pr_list_json "${repo_slug}" "${state}" "${limit}"
    return $?
  fi

  if flow_github_graphql_available "${repo_slug}" \
    && pr_json="$(gh pr list -R "${repo_slug}" --state "${state}" --limit "${limit}" --json number,title,body,url,headRefName,labels,comments,createdAt,mergedAt,isDraft 2>/dev/null)"; then
    printf '%s\n' "${pr_json}"
    return 0
  fi

  if [[ "${state}" == "merged" ]]; then
    pulls_state="closed"
  fi
  if [[ "${limit}" =~ ^[0-9]+$ ]] && (( limit > 0 && limit < 100 )); then
    per_page="${limit}"
  fi

  pull_pages_json="$(flow_github_api_repo "${repo_slug}" "pulls?state=${pulls_state}&per_page=${per_page}" --paginate --slurp 2>/dev/null || true)"
  pull_pages_json="$(flow_json_or_default "${pull_pages_json}" '[]')"

  selected_prs_json="$(
    PULL_PAGES_JSON="${pull_pages_json}" PR_LIMIT="${limit}" PR_STATE_FILTER="${state}" python3 - <<'PY'
import json
import os

pages = json.loads(os.environ.get("PULL_PAGES_JSON", "[]") or "[]")
limit = int(os.environ.get("PR_LIMIT", "100") or "100")
state_filter = os.environ.get("PR_STATE_FILTER", "open")
pulls = []

for page in pages:
    if isinstance(page, list):
        pulls.extend(page)
    elif isinstance(page, dict):
        pulls.append(page)

result = []
for pr in pulls:
    if not isinstance(pr, dict):
        continue
    if state_filter == "merged" and not pr.get("merged_at"):
        continue
    result.append({
        "number": pr.get("number"),
        "title": pr.get("title") or "",
        "body": pr.get("body") or "",
        "url": pr.get("html_url") or pr.get("url") or "",
        "headRefName": ((pr.get("head") or {}).get("ref")) or "",
        "createdAt": pr.get("created_at") or "",
        "mergedAt": pr.get("merged_at") or "",
        "isDraft": bool(pr.get("draft")),
    })
    if len(result) >= limit:
        break

print(json.dumps(result))
PY
  )" || selected_prs_json='[]'

  item_jsonl_file="$(mktemp)"
  trap 'rm -f "${item_jsonl_file}"' RETURN

  while IFS= read -r current_pr_json; do
    [[ -n "${current_pr_json}" ]] || continue
    pr_number="$(jq -r '.number // ""' <<<"${current_pr_json}")"
    [[ -n "${pr_number}" ]] || continue
    issue_json="$(flow_github_api_repo "${repo_slug}" "issues/${pr_number}" 2>/dev/null || true)"
    issue_json="$(flow_json_or_default "${issue_json}" '{}')"
    comment_pages_json="$(flow_github_api_repo "${repo_slug}" "issues/${pr_number}/comments?per_page=100" --paginate --slurp 2>/dev/null || true)"
    comment_pages_json="$(flow_json_or_default "${comment_pages_json}" '[]')"
    PR_JSON="${current_pr_json}" ISSUE_JSON="${issue_json}" COMMENT_PAGES_JSON="${comment_pages_json}" python3 - <<'PY' >>"${item_jsonl_file}"
import json
import os

pr = json.loads(os.environ.get("PR_JSON", "{}") or "{}")
issue = json.loads(os.environ.get("ISSUE_JSON", "{}") or "{}")
comment_pages = json.loads(os.environ.get("COMMENT_PAGES_JSON", "[]") or "[]")
comments = []
for page in comment_pages:
    if isinstance(page, list):
        comments.extend(page)
    elif isinstance(page, dict):
        comments.append(page)

result = {
    "number": pr.get("number"),
    "title": pr.get("title") or "",
    "body": pr.get("body") or issue.get("body") or "",
    "url": pr.get("url") or issue.get("html_url") or issue.get("url") or "",
    "headRefName": pr.get("headRefName") or "",
    "createdAt": pr.get("createdAt") or "",
    "mergedAt": pr.get("mergedAt") or "",
    "isDraft": bool(pr.get("isDraft")),
    "labels": [{"name": label.get("name", "")} for label in issue.get("labels", []) if isinstance(label, dict)],
    "comments": [
        {
            "body": comment.get("body") or "",
            "createdAt": comment.get("created_at") or "",
            "updatedAt": comment.get("updated_at") or "",
            "url": comment.get("html_url") or "",
        }
        for comment in comments
        if isinstance(comment, dict)
    ],
}

print(json.dumps(result))
PY
  done < <(jq -c '.[]' <<<"${selected_prs_json}")

  ITEM_JSONL_FILE="${item_jsonl_file}" python3 - <<'PY'
import json
import os

path = os.environ.get("ITEM_JSONL_FILE", "")
items = []
if path:
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            items.append(json.loads(line))

print(json.dumps(items))
PY
}

flow_github_issue_close() {
  local repo_slug="${1:?repo slug required}"
  local issue_id="${2:?issue id required}"
  local comment_body="${3:-}"
  local payload=""

  if flow_using_gitea; then
    if [[ -n "${comment_body}" ]]; then
      flow_github_api_repo "${repo_slug}" "issues/${issue_id}/comments" --method POST -f body="${comment_body}" >/dev/null || return 1
    fi
    payload='{"state":"closed"}'
    printf '%s' "${payload}" | flow_github_api_repo "${repo_slug}" "issues/${issue_id}" --method PATCH --input - >/dev/null
    return $?
  fi

  if [[ -n "${comment_body}" ]]; then
    if gh issue close "${issue_id}" -R "${repo_slug}" --comment "${comment_body}" >/dev/null 2>&1; then
      return 0
    fi
    flow_github_api_repo "${repo_slug}" "issues/${issue_id}/comments" --method POST -f body="${comment_body}" >/dev/null
  else
    if gh issue close "${issue_id}" -R "${repo_slug}" >/dev/null 2>&1; then
      return 0
    fi
  fi

  payload='{"state":"closed"}'
  printf '%s' "${payload}" | flow_github_api_repo "${repo_slug}" "issues/${issue_id}" --method PATCH --input - >/dev/null
}

flow_github_issue_update_body() {
  local repo_slug="${1:?repo slug required}"
  local issue_id="${2:?issue id required}"
  local body_text="${3:?body text required}"
  local payload=""

  payload="$(
    ISSUE_BODY="${body_text}" python3 - <<'PY'
import json
import os

print(json.dumps({"body": os.environ.get("ISSUE_BODY", "")}))
PY
  )"

  printf '%s' "${payload}" | flow_github_api_repo "${repo_slug}" "issues/${issue_id}" --method PATCH --input - >/dev/null
}

flow_github_label_create() {
  local repo_slug="${1:?repo slug required}"
  local label_name="${2:?label name required}"
  local label_description="${3:-}"
  local label_color="${4:-1D76DB}"
  local encoded_label=""

  if gh label create "${label_name}" -R "${repo_slug}" --description "${label_description}" --color "${label_color}" --force >/dev/null 2>&1; then
    return 0
  fi

  if flow_github_api_repo "${repo_slug}" "labels" --method POST -f name="${label_name}" -f description="${label_description}" -f color="${label_color}" >/dev/null 2>&1; then
    return 0
  fi

  encoded_label="$(flow_github_urlencode "${label_name}")"
  flow_github_api_repo "${repo_slug}" "labels/${encoded_label}" --method PATCH -f new_name="${label_name}" -f description="${label_description}" -f color="${label_color}" >/dev/null 2>&1 || true
}

flow_github_issue_create() {
  local repo_slug="${1:?repo slug required}"
  local title="${2:?title required}"
  local body_file="${3:?body file required}"
  local issue_url=""
  local body_text=""

  if flow_using_gitea; then
    body_text="$(cat "${body_file}")"
    issue_url="$(
      ISSUE_TITLE="${title}" ISSUE_BODY="${body_text}" python3 - <<'PY' | flow_github_api_repo "${repo_slug}" "issues" --method POST --input - | jq -r '.html_url // ""'
import json
import os

payload = {
    "title": os.environ.get("ISSUE_TITLE", ""),
    "body": os.environ.get("ISSUE_BODY", ""),
}
print(json.dumps(payload))
PY
    )"
    [[ -n "${issue_url}" ]] || return 1
    printf '%s\n' "${issue_url}"
    return 0
  fi

  if issue_url="$(gh issue create -R "${repo_slug}" --title "${title}" --body-file "${body_file}" 2>/dev/null)"; then
    printf '%s\n' "${issue_url}"
    return 0
  fi

  body_text="$(cat "${body_file}")"
  issue_url="$(
    ISSUE_TITLE="${title}" ISSUE_BODY="${body_text}" python3 - <<'PY' | flow_github_api_repo "${repo_slug}" "issues" --method POST --input - | jq -r '.html_url // ""'
import json
import os

payload = {
    "title": os.environ.get("ISSUE_TITLE", ""),
    "body": os.environ.get("ISSUE_BODY", ""),
}
print(json.dumps(payload))
PY
  )"
  [[ -n "${issue_url}" ]] || return 1
  printf '%s\n' "${issue_url}"
}

flow_github_current_login() {
  if flow_using_gitea; then
    local user_json=""
    local auth_header=""
    local base_url=""

    base_url="$(flow_gitea_base_url)" || return 1
    if [[ -n "${ACP_GITEA_TOKEN:-${GITEA_TOKEN:-}}" ]]; then
      user_json="$(curl -sS -H "Authorization: token ${ACP_GITEA_TOKEN:-${GITEA_TOKEN:-}}" "${base_url}/api/v1/user" 2>/dev/null || true)"
    elif [[ -n "${ACP_GITEA_USERNAME:-${GITEA_USERNAME:-}}" && -n "${ACP_GITEA_PASSWORD:-${GITEA_PASSWORD:-}}" ]]; then
      user_json="$(curl -sS -u "${ACP_GITEA_USERNAME:-${GITEA_USERNAME:-}}:${ACP_GITEA_PASSWORD:-${GITEA_PASSWORD:-}}" "${base_url}/api/v1/user" 2>/dev/null || true)"
    fi
    jq -r '.login // ""' <<<"${user_json:-{}}" 2>/dev/null || true
    return 0
  fi

  gh api user --jq '.login // ""' 2>/dev/null || true
}

flow_github_pr_author_login() {
  local repo_slug="${1:?repo slug required}"
  local pr_number="${2:?pr number required}"

  flow_github_pr_view_json "${repo_slug}" "${pr_number}" 2>/dev/null | jq -r '.authorLogin // ""' 2>/dev/null || true
}

flow_github_pr_head_oid() {
  local repo_slug="${1:?repo slug required}"
  local pr_number="${2:?pr number required}"

  flow_github_pr_view_json "${repo_slug}" "${pr_number}" 2>/dev/null | jq -r '.headRefOid // ""' 2>/dev/null || true
}

flow_github_pr_review_approve() {
  local repo_slug="${1:?repo slug required}"
  local pr_number="${2:?pr number required}"
  local body_text="${3:-Automated final review passed.}"
  local output=""

  if flow_using_gitea; then
    if output="$(
      REVIEW_BODY="${body_text}" python3 - <<'PY' | flow_github_api_repo "${repo_slug}" "pulls/${pr_number}/reviews" --method POST --input - 2>&1
import json
import os

print(json.dumps({"event": "APPROVED", "body": os.environ.get("REVIEW_BODY", "")}))
PY
    )"; then
      return 0
    fi
    if grep -q "approve your own pull is not allowed" <<<"${output}"; then
      return 0
    fi
    printf '%s\n' "${output}" >&2
    return 1
  fi

  gh api "repos/${repo_slug}/pulls/${pr_number}/reviews" --method POST -f event=APPROVE -f body="${body_text}" >/dev/null
}

flow_github_pr_create() {
  local repo_slug="${1:?repo slug required}"
  local base_branch="${2:?base branch required}"
  local head_branch="${3:?head branch required}"
  local title="${4:?title required}"
  local body_file="${5:?body file required}"
  local pr_url=""
  local body_text=""

  if flow_using_gitea; then
    body_text="$(cat "${body_file}")"
    pr_url="$(
      BASE_BRANCH="${base_branch}" HEAD_BRANCH="${head_branch}" PR_TITLE="${title}" PR_BODY="${body_text}" python3 - <<'PY' | flow_github_api_repo "${repo_slug}" "pulls" --method POST --input - | jq -r '.html_url // ""'
import json
import os

payload = {
    "title": os.environ.get("PR_TITLE", ""),
    "head": os.environ.get("HEAD_BRANCH", ""),
    "base": os.environ.get("BASE_BRANCH", ""),
    "body": os.environ.get("PR_BODY", ""),
}
print(json.dumps(payload))
PY
    )"
    [[ -n "${pr_url}" ]] || return 1
    printf '%s\n' "${pr_url}"
    return 0
  fi

  if pr_url="$(gh pr create -R "${repo_slug}" --base "${base_branch}" --head "${head_branch}" --title "${title}" --body-file "${body_file}" 2>/dev/null)"; then
    printf '%s\n' "${pr_url}"
    return 0
  fi

  body_text="$(cat "${body_file}")"
  pr_url="$(
    BASE_BRANCH="${base_branch}" HEAD_BRANCH="${head_branch}" PR_TITLE="${title}" PR_BODY="${body_text}" python3 - <<'PY' | flow_github_api_repo "${repo_slug}" "pulls" --method POST --input - | jq -r '.html_url // ""'
import json
import os

payload = {
    "title": os.environ.get("PR_TITLE", ""),
    "head": os.environ.get("HEAD_BRANCH", ""),
    "base": os.environ.get("BASE_BRANCH", ""),
    "body": os.environ.get("PR_BODY", ""),
}
print(json.dumps(payload))
PY
  )"
  [[ -n "${pr_url}" ]] || return 1
  printf '%s\n' "${pr_url}"
}

