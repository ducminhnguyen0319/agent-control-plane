#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-shell-lib.sh"
flow_export_project_env_aliases

flow_explicit_github_repo_id() {
  local requested_repo_slug="${1:-}"
  local configured_repo_slug="${ACP_REPO_SLUG:-${F_LOSNING_REPO_SLUG:-}}"
  local explicit_repo_id="${ACP_REPO_ID:-${F_LOSNING_REPO_ID:-${ACP_GITHUB_REPOSITORY_ID:-${F_LOSNING_GITHUB_REPOSITORY_ID:-}}}}"

  [[ -n "${explicit_repo_id}" ]] || return 1
  if [[ -n "${requested_repo_slug}" && -n "${configured_repo_slug}" && "${configured_repo_slug}" != "${requested_repo_slug}" ]]; then
    return 1
  fi

  printf '%s\n' "${explicit_repo_id}"
}

flow_explicit_profile_id() {
  printf '%s\n' "${ACP_PROJECT_ID:-${AGENT_PROJECT_ID:-}}"
}

resolve_flow_profile_registry_root() {
  local platform_home="${AGENT_PLATFORM_HOME:-${HOME}/.agent-runtime}"
  printf '%s\n' "${AGENT_CONTROL_PLANE_PROFILE_ROOT:-${ACP_PROFILE_REGISTRY_ROOT:-${platform_home}/control-plane/profiles}}"
}

flow_list_profiles_in_root() {
  local profiles_root="${1:-}"
  local profile_file=""
  local profile_id=""

  [[ -d "${profiles_root}" ]] || return 0

  while IFS= read -r profile_file; do
    [[ -n "${profile_file}" ]] || continue
    profile_id="$(basename "$(dirname "${profile_file}")")"
    [[ -n "${profile_id}" ]] || continue
    printf '%s\n' "${profile_id}"
  done < <(find "${profiles_root}" -mindepth 2 -maxdepth 2 -type f -name 'control-plane.yaml' 2>/dev/null | sort)
}

flow_list_installed_profile_ids() {
  flow_list_profiles_in_root "$(resolve_flow_profile_registry_root)"
}

flow_find_profile_dir_by_id() {
  local flow_root="${1:-}"
  local profile_id="${2:?profile id required}"
  local registry_root=""
  local candidate=""

  if [[ -z "${flow_root}" ]]; then
    flow_root="$(resolve_flow_skill_dir "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  registry_root="$(resolve_flow_profile_registry_root)"
  candidate="${registry_root}/${profile_id}"
  if [[ -f "${candidate}/control-plane.yaml" ]]; then
    printf '%s\n' "${candidate}"
    return 0
  fi

  printf '%s/%s\n' "${registry_root}" "${profile_id}"
}

flow_profile_count() {
  local flow_root="${1:-}"

  if [[ -z "${flow_root}" ]]; then
    flow_root="$(resolve_flow_skill_dir "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  flow_list_profile_ids "${flow_root}" | awk 'NF { count += 1 } END { print count + 0 }'
}

flow_default_profile_id() {
  local flow_root="${1:-}"
  local preferred_profile="${AGENT_CONTROL_PLANE_DEFAULT_PROFILE_ID:-${ACP_DEFAULT_PROFILE_ID:-${AGENT_PROJECT_DEFAULT_PROFILE_ID:-}}}"
  local candidate=""

  if [[ -z "${flow_root}" ]]; then
    flow_root="$(resolve_flow_skill_dir "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  for candidate in "${preferred_profile}" "default"; do
    [[ -n "${candidate}" ]] || continue
    if [[ -f "$(flow_find_profile_dir_by_id "${flow_root}" "${candidate}")/control-plane.yaml" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  candidate="$(flow_list_profile_ids "${flow_root}" | grep -v '^demo$' | head -n 1 || true)"
  if [[ -n "${candidate}" ]]; then
    printf '%s\n' "${candidate}"
    return 0
  fi

  candidate="$(flow_list_profile_ids "${flow_root}" | head -n 1 || true)"
  if [[ -n "${candidate}" ]]; then
    printf '%s\n' "${candidate}"
    return 0
  fi

  printf 'default\n'
}

flow_profile_selection_mode() {
  local flow_root="${1:-}"
  local explicit_profile=""
  local profile_count="0"

  if [[ -z "${flow_root}" ]]; then
    flow_root="$(resolve_flow_skill_dir "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  explicit_profile="$(flow_explicit_profile_id)"
  if [[ -n "${explicit_profile}" ]]; then
    printf 'explicit\n'
    return 0
  fi

  profile_count="$(flow_profile_count "${flow_root}")"
  if [[ "${profile_count}" -gt 1 ]]; then
    printf 'implicit-default\n'
    return 0
  fi

  printf 'single-profile-default\n'
}

flow_profile_selection_hint() {
  local flow_root="${1:-}"
  local mode=""

  if [[ -z "${flow_root}" ]]; then
    flow_root="$(resolve_flow_skill_dir "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  mode="$(flow_profile_selection_mode "${flow_root}")"
  if [[ "${mode}" == "implicit-default" ]]; then
    printf 'Set ACP_PROJECT_ID=<id> or AGENT_PROJECT_ID=<id> when multiple available profiles exist.\n'
  fi
}

flow_profile_guard_message() {
  local flow_root="${1:-}"
  local command_name="${2:-this command}"
  local hint=""

  if [[ -z "${flow_root}" ]]; then
    flow_root="$(resolve_flow_skill_dir "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  hint="$(flow_profile_selection_hint "${flow_root}")"
  printf 'explicit profile selection required for %s when multiple available profiles exist.\n' "${command_name}"
  if [[ -n "${hint}" ]]; then
    printf '%s\n' "${hint}"
  fi
}

flow_require_explicit_profile_selection() {
  local flow_root="${1:-}"
  local command_name="${2:-this command}"

  if [[ -z "${flow_root}" ]]; then
    flow_root="$(resolve_flow_skill_dir "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  if [[ "${ACP_ALLOW_IMPLICIT_PROFILE_SELECTION:-0}" == "1" ]]; then
    return 0
  fi

  if [[ "$(flow_profile_selection_mode "${flow_root}")" == "implicit-default" ]]; then
    flow_profile_guard_message "${flow_root}" "${command_name}" >&2
    return 1
  fi

  return 0
}

resolve_flow_config_yaml() {
  local script_path="${1:-${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}}"
  local flow_root
  local profile_id=""
  local candidate=""
  flow_root="$(resolve_flow_skill_dir "${script_path}")"
  profile_id="${ACP_PROJECT_ID:-${AGENT_PROJECT_ID:-$(flow_default_profile_id "${flow_root}")}}"

  for candidate in \
    "${AGENT_CONTROL_PLANE_CONFIG:-}" \
    "${ACP_CONFIG:-}" \
    "${AGENT_PROJECT_CONFIG_PATH:-}" \
    "${F_LOSNING_FLOW_CONFIG:-}"; do
    if [[ -n "${candidate}" && -f "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  candidate="$(flow_find_profile_dir_by_id "${flow_root}" "${profile_id}")/control-plane.yaml"
  if [[ -f "${candidate}" ]]; then
    printf '%s\n' "${candidate}"
    return 0
  fi

  printf '%s\n' "${candidate}"
}

flow_list_profile_ids() {
  local flow_root="${1:-}"
  local found_any=""

  if [[ -z "${flow_root}" ]]; then
    flow_root="$(resolve_flow_skill_dir "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  found_any="$(
    {
      flow_list_installed_profile_ids
    } | awk 'NF { print }' | sort -u
  )"

  if [[ -z "${found_any}" ]]; then
    return 0
  fi

  printf '%s\n' "${found_any}"
}

flow_git_remote_repo_slug() {
  local repo_root="${1:-}"
  local remote_name="${2:-origin}"
  local remote_url=""
  local normalized=""

  [[ -n "${repo_root}" && -d "${repo_root}" ]] || return 1
  remote_url="$(git -C "${repo_root}" remote get-url "${remote_name}" 2>/dev/null || true)"
  [[ -n "${remote_url}" ]] || return 1

  normalized="${remote_url%.git}"
  case "${normalized}" in
    ssh://*@*/*)
      normalized="${normalized#ssh://}"
      normalized="${normalized#*@}"
      normalized="${normalized#*/}"
      ;;
    *@*:*/*)
      normalized="${normalized#*@}"
      normalized="${normalized#*:}"
      ;;
    https://*/*|http://*/*)
      normalized="${normalized#http://}"
      normalized="${normalized#https://}"
      normalized="${normalized#*/}"
      ;;
    *)
      return 1
      ;;
  esac

  if [[ "${normalized}" == */*/* ]]; then
    normalized="${normalized#*/}"
  fi

  if [[ "${normalized}" =~ ^[^/]+/[^/]+$ ]]; then
    printf '%s\n' "${normalized}"
    return 0
  fi

  return 1
}

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
  if [[ "${#auth_args[@]}" -eq 0 ]]; then
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

flow_github_pr_merge() {
  local repo_slug="${1:?repo slug required}"
  local pr_number="${2:?pr number required}"
  local merge_method="${3:-squash}"
  local delete_branch="${4:-no}"
  local pr_json=""
  local head_ref=""
  local encoded_ref=""

  if flow_using_gitea; then
    printf '%s' "$(
      MERGE_METHOD="${merge_method}" DELETE_BRANCH="${delete_branch}" python3 - <<'PY'
import json
import os

method = os.environ.get("MERGE_METHOD", "squash")
delete_branch = os.environ.get("DELETE_BRANCH", "no") == "yes"
method_map = {"merge": "merge", "squash": "squash", "rebase": "rebase"}
print(json.dumps({
    "Do": method_map.get(method, "squash"),
    "delete_branch_after_merge": delete_branch,
}))
PY
    )" | flow_github_api_repo "${repo_slug}" "pulls/${pr_number}/merge" --method POST --input - >/dev/null
    return $?
  fi

  if gh pr merge "${pr_number}" -R "${repo_slug}" "--${merge_method}" $([[ "${delete_branch}" == "yes" ]] && printf '%s' '--delete-branch') --admin >/dev/null 2>&1; then
    return 0
  fi

  printf '{"merge_method":"%s"}' "${merge_method}" \
    | flow_github_api_repo "${repo_slug}" "pulls/${pr_number}/merge" --method PUT --input - >/dev/null

  if [[ "${delete_branch}" == "yes" ]]; then
    pr_json="$(flow_github_pr_view_json "${repo_slug}" "${pr_number}" 2>/dev/null || printf '{}\n')"
    head_ref="$(jq -r '.headRefName // ""' <<<"${pr_json}")"
    if [[ -n "${head_ref}" ]]; then
      encoded_ref="$(flow_github_urlencode "heads/${head_ref}")"
      flow_github_api_repo "${repo_slug}" "git/refs/${encoded_ref}" --method DELETE >/dev/null 2>&1 || true
    fi
  fi
}

flow_config_get() {
  local config_file="${1:?config file required}"
  local target_path="${2:?target path required}"

  python3 - "$config_file" "$target_path" <<'PY'
import sys

config_file = sys.argv[1]
target_path = sys.argv[2]

stack = []
found = False

with open(config_file, "r", encoding="utf-8") as fh:
    for raw_line in fh:
        stripped = raw_line.strip()
        if not stripped or stripped.startswith("#") or stripped.startswith("- "):
            continue
        if ":" not in raw_line:
            continue

        indent = len(raw_line) - len(raw_line.lstrip())
        key, value = stripped.split(":", 1)
        key = key.strip()
        value = value.strip().strip("\"'")

        while stack and indent <= stack[-1][0]:
            stack.pop()

        stack.append((indent, key))
        current_path = ".".join(part for _, part in stack)

        if current_path == target_path and value:
            print(value)
            found = True
            break

if not found:
    print("")
PY
}

flow_kv_get() {
  local payload="${1:-}"
  local key="${2:?key required}"

  awk -F= -v key="${key}" '$1 == key { print substr($0, length(key) + 2); exit }' <<<"${payload}"
}

flow_env_or_config() {
  local config_file="${1:?config file required}"
  local env_names="${2:?env names required}"
  local config_key="${3:?config key required}"
  local default_value="${4:-}"
  local env_name=""
  local value=""

  for env_name in ${env_names}; do
    value="${!env_name:-}"
    if [[ -n "${value}" ]]; then
      printf '%s\n' "${value}"
      return 0
    fi
  done

  if [[ -f "${config_file}" ]]; then
    value="$(flow_config_get "${config_file}" "${config_key}")"
    if [[ -n "${value}" ]]; then
      printf '%s\n' "${value}"
      return 0
    fi
  fi

  printf '%s\n' "${default_value}"
}

flow_resolve_adapter_id() {
  local config_file="${1:-}"
  local default_value=""
  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi
  default_value="$(flow_default_profile_id)"
  flow_env_or_config "${config_file}" "ACP_PROJECT_ID AGENT_PROJECT_ID" "id" "${default_value}"
}

flow_resolve_profile_notes_file() {
  local config_file="${1:-}"
  local config_dir=""

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  config_dir="$(cd "$(dirname "${config_file}")" 2>/dev/null && pwd -P || dirname "${config_file}")"
  printf '%s/README.md
' "${config_dir}"
}

flow_default_issue_session_prefix() {
  local config_file="${1:-}"
  local adapter_id=""

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  adapter_id="$(flow_resolve_adapter_id "${config_file}")"
  printf '%s-issue-\n' "${adapter_id}"
}

flow_default_pr_session_prefix() {
  local config_file="${1:-}"
  local adapter_id=""

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  adapter_id="$(flow_resolve_adapter_id "${config_file}")"
  printf '%s-pr-\n' "${adapter_id}"
}

flow_default_issue_branch_prefix() {
  local config_file="${1:-}"
  local adapter_id=""

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  adapter_id="$(flow_resolve_adapter_id "${config_file}")"
  printf 'agent/%s/issue\n' "${adapter_id}"
}

flow_default_pr_worktree_branch_prefix() {
  local config_file="${1:-}"
  local adapter_id=""

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  adapter_id="$(flow_resolve_adapter_id "${config_file}")"
  printf 'agent/%s/pr\n' "${adapter_id}"
}

flow_default_managed_pr_branch_globs() {
  local config_file="${1:-}"
  local adapter_id=""

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  adapter_id="$(flow_resolve_adapter_id "${config_file}")"
  printf 'agent/%s/* codex/* openclaw/*\n' "${adapter_id}"
}

flow_default_agent_root() {
  local config_file="${1:-}"
  local adapter_id=""
  local platform_home="${AGENT_PLATFORM_HOME:-${HOME}/.agent-runtime}"

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  adapter_id="$(flow_resolve_adapter_id "${config_file}")"
  printf '%s/projects/%s
' "${platform_home}" "${adapter_id}"
}

flow_default_repo_slug() {
  local config_file="${1:-}"
  local adapter_id=""

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  adapter_id="$(flow_resolve_adapter_id "${config_file}")"
  printf 'example/%s
' "${adapter_id}"
}

flow_default_repo_id() {
  printf '\n'
}

flow_default_repo_root() {
  local config_file="${1:-}"
  local agent_root=""

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  agent_root="$(flow_default_agent_root "${config_file}")"
  printf '%s/repo
' "${agent_root}"
}

flow_default_worktree_root() {
  local config_file="${1:-}"
  local agent_root=""

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  agent_root="$(flow_default_agent_root "${config_file}")"
  printf '%s/worktrees
' "${agent_root}"
}

flow_default_retained_repo_root() {
  local config_file="${1:-}"
  local agent_root=""

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  agent_root="$(flow_default_agent_root "${config_file}")"
  printf '%s/retained
' "${agent_root}"
}

flow_default_vscode_workspace_file() {
  local config_file="${1:-}"
  local agent_root=""

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  agent_root="$(flow_default_agent_root "${config_file}")"
  printf '%s/workspace.code-workspace
' "${agent_root}"
}
flow_resolve_repo_slug() {
  local config_file="${1:-}"
  local default_value=""
  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi
  default_value="$(flow_default_repo_slug "${config_file}")"
  flow_env_or_config "${config_file}" "ACP_REPO_SLUG F_LOSNING_REPO_SLUG" "repo.slug" "${default_value}"
}

flow_resolve_repo_id() {
  local config_file="${1:-}"
  local default_value=""
  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi
  default_value="$(flow_default_repo_id)"
  flow_env_or_config "${config_file}" "ACP_REPO_ID F_LOSNING_REPO_ID ACP_GITHUB_REPOSITORY_ID F_LOSNING_GITHUB_REPOSITORY_ID" "repo.id" "${default_value}"
}

flow_resolve_default_branch() {
  local config_file="${1:-}"
  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi
  flow_env_or_config "${config_file}" "ACP_DEFAULT_BRANCH F_LOSNING_DEFAULT_BRANCH" "repo.default_branch" "main"
}

flow_resolve_project_label() {
  local config_file="${1:-}"
  local repo_slug=""
  local adapter_id=""
  local label=""

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  repo_slug="$(flow_resolve_repo_slug "${config_file}")"
  adapter_id="$(flow_resolve_adapter_id "${config_file}")"
  label="${repo_slug##*/}"
  if [[ -n "${label}" ]]; then
    printf '%s\n' "${label}"
  else
    printf '%s\n' "${adapter_id}"
  fi
}

flow_resolve_repo_root() {
  local config_file="${1:-}"
  local default_value=""
  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi
  default_value="$(flow_default_repo_root "${config_file}")"
  flow_env_or_config "${config_file}" "ACP_REPO_ROOT F_LOSNING_REPO_ROOT" "repo.root" "${default_value}"
}

flow_resolve_agent_root() {
  local config_file="${1:-}"
  local default_value=""

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  default_value="$(flow_default_agent_root "${config_file}")"
  flow_env_or_config "${config_file}" "ACP_AGENT_ROOT F_LOSNING_AGENT_ROOT" "runtime.orchestrator_agent_root" "${default_value}"
}

flow_resolve_agent_repo_root() {
  local config_file="${1:-}"
  local default_value=""

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  default_value="$(flow_resolve_repo_root "${config_file}")"
  flow_env_or_config "${config_file}" "ACP_AGENT_REPO_ROOT F_LOSNING_AGENT_REPO_ROOT" "runtime.agent_repo_root" "${default_value}"
}

flow_resolve_worktree_root() {
  local config_file="${1:-}"
  local default_value=""
  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi
  default_value="$(flow_default_worktree_root "${config_file}")"
  flow_env_or_config "${config_file}" "ACP_WORKTREE_ROOT F_LOSNING_WORKTREE_ROOT" "runtime.worktree_root" "${default_value}"
}

flow_resolve_runs_root() {
  local config_file="${1:-}"
  local default_value=""
  local explicit_root="${ACP_RUNS_ROOT:-${F_LOSNING_RUNS_ROOT:-}}"
  local umbrella_root="${ACP_AGENT_ROOT:-${F_LOSNING_AGENT_ROOT:-}}"

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  if [[ -n "${explicit_root}" ]]; then
    printf '%s\n' "${explicit_root}"
    return 0
  fi

  default_value="$(flow_resolve_agent_root "${config_file}")/runs"
  if [[ -n "${umbrella_root}" ]]; then
    printf '%s\n' "${default_value}"
    return 0
  fi

  flow_env_or_config "${config_file}" "ACP_RUNS_ROOT F_LOSNING_RUNS_ROOT" "runtime.runs_root" "${default_value}"
}

flow_resolve_state_root() {
  local config_file="${1:-}"
  local default_value=""
  local explicit_root="${ACP_STATE_ROOT:-${F_LOSNING_STATE_ROOT:-}}"
  local umbrella_root="${ACP_AGENT_ROOT:-${F_LOSNING_AGENT_ROOT:-}}"

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  if [[ -n "${explicit_root}" ]]; then
    printf '%s\n' "${explicit_root}"
    return 0
  fi

  default_value="$(flow_resolve_agent_root "${config_file}")/state"
  if [[ -n "${umbrella_root}" ]]; then
    printf '%s\n' "${default_value}"
    return 0
  fi

  flow_env_or_config "${config_file}" "ACP_STATE_ROOT F_LOSNING_STATE_ROOT" "runtime.state_root" "${default_value}"
}

flow_resolve_history_root() {
  local config_file="${1:-}"
  local default_value=""
  local explicit_root="${ACP_HISTORY_ROOT:-${F_LOSNING_HISTORY_ROOT:-}}"
  local umbrella_root="${ACP_AGENT_ROOT:-${F_LOSNING_AGENT_ROOT:-}}"

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  if [[ -n "${explicit_root}" ]]; then
    printf '%s\n' "${explicit_root}"
    return 0
  fi

  default_value="$(flow_resolve_agent_root "${config_file}")/history"
  if [[ -n "${umbrella_root}" ]]; then
    printf '%s\n' "${default_value}"
    return 0
  fi

  flow_env_or_config "${config_file}" "ACP_HISTORY_ROOT F_LOSNING_HISTORY_ROOT" "runtime.history_root" "${default_value}"
}

flow_resolve_retained_repo_root() {
  local config_file="${1:-}"
  local default_value=""
  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi
  default_value="$(flow_default_retained_repo_root "${config_file}")"
  flow_env_or_config "${config_file}" "ACP_RETAINED_REPO_ROOT F_LOSNING_RETAINED_REPO_ROOT" "runtime.retained_repo_root" "${default_value}"
}

flow_resolve_vscode_workspace_file() {
  local config_file="${1:-}"
  local default_value=""
  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi
  default_value="$(flow_default_vscode_workspace_file "${config_file}")"
  flow_env_or_config "${config_file}" "ACP_VSCODE_WORKSPACE_FILE F_LOSNING_VSCODE_WORKSPACE_FILE" "runtime.vscode_workspace_file" "${default_value}"
}

flow_resolve_web_playwright_command() {
  local config_file="${1:-}"
  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi
  flow_env_or_config "${config_file}" "ACP_WEB_PLAYWRIGHT_COMMAND F_LOSNING_WEB_PLAYWRIGHT_COMMAND" "execution.verification.web_playwright_command" "pnpm exec playwright test"
}

flow_resolve_codex_quota_bin() {
  local flow_root="${1:-}"
  local shared_home=""
  local explicit_bin="${ACP_CODEX_QUOTA_BIN:-${F_LOSNING_CODEX_QUOTA_BIN:-}}"
  local candidate=""

  if [[ -n "${explicit_bin}" ]]; then
    printf '%s\n' "${explicit_bin}"
    return 0
  fi

  if [[ -z "${flow_root}" ]]; then
    flow_root="$(resolve_flow_skill_dir "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi
  shared_home="${SHARED_AGENT_HOME:-$(resolve_shared_agent_home "${flow_root}")}"

  for candidate in \
    "${flow_root}/tools/bin/codex-quota" \
    "${shared_home}/tools/bin/codex-quota"; do
    if [[ -x "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  candidate="$(command -v codex-quota 2>/dev/null || true)"
  if [[ -n "${candidate}" ]]; then
    printf '%s\n' "${candidate}"
    return 0
  fi

  printf '%s\n' "${flow_root}/tools/bin/codex-quota"
}

flow_resolve_codex_quota_manager_script() {
  local flow_root="${1:-}"
  local shared_home=""
  local explicit_script="${ACP_CODEX_QUOTA_MANAGER_SCRIPT:-${F_LOSNING_CODEX_QUOTA_MANAGER_SCRIPT:-}}"
  local candidate=""

  if [[ -n "${explicit_script}" ]]; then
    printf '%s\n' "${explicit_script}"
    return 0
  fi

  if [[ -z "${flow_root}" ]]; then
    flow_root="$(resolve_flow_skill_dir "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi
  shared_home="${SHARED_AGENT_HOME:-$(resolve_shared_agent_home "${flow_root}")}"

  for candidate in \
    "${flow_root}/tools/vendor/codex-quota-manager/scripts/auto-switch.sh" \
    "${shared_home}/tools/vendor/codex-quota-manager/scripts/auto-switch.sh" \
    "${shared_home}/skills/openclaw/codex-quota-manager/scripts/auto-switch.sh"; do
    if [[ -x "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  printf '%s\n' "${flow_root}/tools/vendor/codex-quota-manager/scripts/auto-switch.sh"
}

flow_resolve_template_file() {
  local template_name="${1:?template name required}"
  local workspace_dir="${2:-}"
  local config_file="${3:-}"
  local flow_root=""
  local profile_id=""
  local config_dir=""
  local template_dir=""
  local candidate=""
  local workspace_real=""
  local canonical_tools_real=""

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  flow_root="$(resolve_flow_skill_dir "${BASH_SOURCE[0]}")"
  config_dir="$(cd "$(dirname "${config_file}")" 2>/dev/null && pwd -P || dirname "${config_file}")"

  for template_dir in \
    "${AGENT_CONTROL_PLANE_TEMPLATE_DIR:-}" \
    "${ACP_TEMPLATE_DIR:-}" \
    "${F_LOSNING_TEMPLATE_DIR:-}"; do
    if [[ -n "${template_dir}" && -f "${template_dir}/${template_name}" ]]; then
      printf '%s\n' "${template_dir}/${template_name}"
      return 0
    fi
  done

  if [[ -n "${workspace_dir}" && -f "${workspace_dir}/templates/${template_name}" ]]; then
    workspace_real="$(cd "${workspace_dir}" && pwd -P)"
    canonical_tools_real="$(cd "${flow_root}/tools" && pwd -P)"
    if [[ "${workspace_real}" != "${canonical_tools_real}" ]]; then
      printf '%s\n' "${workspace_dir}/templates/${template_name}"
      return 0
    fi
  fi

  candidate="${config_dir}/templates/${template_name}"
  if [[ -f "${candidate}" ]]; then
    printf '%s\n' "${candidate}"
    return 0
  fi

  if [[ -n "${workspace_dir}" && -f "${workspace_dir}/templates/${template_name}" ]]; then
    printf '%s\n' "${workspace_dir}/templates/${template_name}"
    return 0
  fi

  printf '%s\n' "${flow_root}/tools/templates/${template_name}"
}

flow_resolve_retry_cooldowns() {
  local config_file="${1:-}"
  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi
  flow_env_or_config "${config_file}" "ACP_RETRY_COOLDOWNS F_LOSNING_RETRY_COOLDOWNS" "execution.retry.cooldowns" "300,900,1800,3600"
}

flow_resolve_provider_quota_cooldowns() {
  local config_file="${1:-}"
  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi
  flow_env_or_config "${config_file}" "ACP_PROVIDER_QUOTA_COOLDOWNS F_LOSNING_PROVIDER_QUOTA_COOLDOWNS" "execution.provider_quota.cooldowns" "300,900,1800,3600"
}

flow_resolve_provider_pool_order() {
  local config_file="${1:-}"
  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi
  flow_env_or_config "${config_file}" "ACP_PROVIDER_POOL_ORDER F_LOSNING_PROVIDER_POOL_ORDER" "execution.provider_pool_order" ""
}

flow_provider_pool_names() {
  local config_file="${1:-}"
  local order=""
  local pool_name=""

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  order="$(flow_resolve_provider_pool_order "${config_file}")"
  for pool_name in ${order}; do
    [[ -n "${pool_name}" ]] || continue
    printf '%s\n' "${pool_name}"
  done
}

flow_provider_pools_enabled() {
  local config_file="${1:-}"
  [[ -n "$(flow_resolve_provider_pool_order "${config_file}")" ]]
}

flow_provider_pool_value() {
  local config_file="${1:?config file required}"
  local pool_name="${2:?pool name required}"
  local relative_path="${3:?relative path required}"

  flow_config_get "${config_file}" "execution.provider_pools.${pool_name}.${relative_path}"
}

flow_provider_pool_backend() {
  local config_file="${1:?config file required}"
  local pool_name="${2:?pool name required}"

  flow_provider_pool_value "${config_file}" "${pool_name}" "coding_worker"
}

flow_provider_pool_safe_profile() {
  local config_file="${1:?config file required}"
  local pool_name="${2:?pool name required}"

  flow_provider_pool_value "${config_file}" "${pool_name}" "safe_profile"
}

flow_provider_pool_bypass_profile() {
  local config_file="${1:?config file required}"
  local pool_name="${2:?pool name required}"

  flow_provider_pool_value "${config_file}" "${pool_name}" "bypass_profile"
}

flow_provider_pool_claude_model() {
  local config_file="${1:?config file required}"
  local pool_name="${2:?pool name required}"

  flow_provider_pool_value "${config_file}" "${pool_name}" "claude.model"
}

flow_provider_pool_claude_permission_mode() {
  local config_file="${1:?config file required}"
  local pool_name="${2:?pool name required}"

  flow_provider_pool_value "${config_file}" "${pool_name}" "claude.permission_mode"
}

flow_provider_pool_claude_effort() {
  local config_file="${1:?config file required}"
  local pool_name="${2:?pool name required}"

  flow_provider_pool_value "${config_file}" "${pool_name}" "claude.effort"
}

flow_provider_pool_claude_timeout_seconds() {
  local config_file="${1:?config file required}"
  local pool_name="${2:?pool name required}"

  flow_provider_pool_value "${config_file}" "${pool_name}" "claude.timeout_seconds"
}

flow_provider_pool_claude_max_attempts() {
  local config_file="${1:?config file required}"
  local pool_name="${2:?pool name required}"

  flow_provider_pool_value "${config_file}" "${pool_name}" "claude.max_attempts"
}

flow_provider_pool_claude_retry_backoff_seconds() {
  local config_file="${1:?config file required}"
  local pool_name="${2:?pool name required}"

  flow_provider_pool_value "${config_file}" "${pool_name}" "claude.retry_backoff_seconds"
}

flow_provider_pool_openclaw_model() {
  local config_file="${1:?config file required}"
  local pool_name="${2:?pool name required}"

  flow_provider_pool_value "${config_file}" "${pool_name}" "openclaw.model"
}

flow_provider_pool_openclaw_thinking() {
  local config_file="${1:?config file required}"
  local pool_name="${2:?pool name required}"

  flow_provider_pool_value "${config_file}" "${pool_name}" "openclaw.thinking"
}

flow_provider_pool_openclaw_timeout_seconds() {
  local config_file="${1:?config file required}"
  local pool_name="${2:?pool name required}"

  flow_provider_pool_value "${config_file}" "${pool_name}" "openclaw.timeout_seconds"
}

flow_provider_pool_ollama_model() {
  local config_file="${1:?config file required}"
  local pool_name="${2:?pool name required}"

  flow_provider_pool_value "${config_file}" "${pool_name}" "ollama.model"
}

flow_provider_pool_ollama_base_url() {
  local config_file="${1:?config file required}"
  local pool_name="${2:?pool name required}"

  flow_provider_pool_value "${config_file}" "${pool_name}" "ollama.base_url"
}

flow_provider_pool_ollama_timeout_seconds() {
  local config_file="${1:?config file required}"
  local pool_name="${2:?pool name required}"

  flow_provider_pool_value "${config_file}" "${pool_name}" "ollama.timeout_seconds"
}

flow_provider_pool_pi_model() {
  local config_file="${1:?config file required}"
  local pool_name="${2:?pool name required}"

  flow_provider_pool_value "${config_file}" "${pool_name}" "pi.model"
}

flow_provider_pool_pi_thinking() {
  local config_file="${1:?config file required}"
  local pool_name="${2:?pool name required}"

  flow_provider_pool_value "${config_file}" "${pool_name}" "pi.thinking"
}

flow_provider_pool_pi_timeout_seconds() {
  local config_file="${1:?config file required}"
  local pool_name="${2:?pool name required}"

  flow_provider_pool_value "${config_file}" "${pool_name}" "pi.timeout_seconds"
}

flow_provider_pool_opencode_model() {
  local config_file="${1:?config file required}"
  local pool_name="${2:?pool name required}"

  flow_provider_pool_value "${config_file}" "${pool_name}" "opencode.model"
}

flow_provider_pool_opencode_timeout_seconds() {
  local config_file="${1:?config file required}"
  local pool_name="${2:?pool name required}"

  flow_provider_pool_value "${config_file}" "${pool_name}" "opencode.timeout_seconds"
}

flow_provider_pool_kilo_model() {
  local config_file="${1:?config file required}"
  local pool_name="${2:?pool name required}"

  flow_provider_pool_value "${config_file}" "${pool_name}" "kilo.model"
}

flow_provider_pool_kilo_timeout_seconds() {
  local config_file="${1:?config file required}"
  local pool_name="${2:?pool name required}"

  flow_provider_pool_value "${config_file}" "${pool_name}" "kilo.timeout_seconds"
}

flow_sanitize_provider_key() {
  local raw_key="${1:?raw key required}"

  printf '%s' "${raw_key}" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9._-]+/-/g; s/^-+//; s/-+$//; s/-+/-/g'
}

flow_provider_pool_model_identity() {
  local config_file="${1:?config file required}"
  local pool_name="${2:?pool name required}"
  local backend=""

  backend="$(flow_provider_pool_backend "${config_file}" "${pool_name}")"
  case "${backend}" in
    codex)
      flow_provider_pool_safe_profile "${config_file}" "${pool_name}"
      ;;
    claude)
      flow_provider_pool_claude_model "${config_file}" "${pool_name}"
      ;;
    openclaw)
      flow_provider_pool_openclaw_model "${config_file}" "${pool_name}"
      ;;
    ollama)
      flow_provider_pool_ollama_model "${config_file}" "${pool_name}"
      ;;
    pi)
      flow_provider_pool_pi_model "${config_file}" "${pool_name}"
      ;;
    opencode)
      flow_provider_pool_opencode_model "${config_file}" "${pool_name}"
      ;;
    kilo)
      flow_provider_pool_kilo_model "${config_file}" "${pool_name}"
      ;;
    *)
      printf '\n'
      ;;
  esac
}

flow_provider_pool_state_get() {
  local config_file="${1:?config file required}"
  local pool_name="${2:?pool name required}"
  local backend=""
  local model=""
  local state_root=""
  local provider_key=""
  local state_file=""
  local attempts="0"
  local next_attempt_epoch="0"
  local next_attempt_at=""
  local last_reason=""
  local updated_at=""
  local ready="yes"
  local valid="yes"
  local now_epoch=""
  local safe_profile=""
  local bypass_profile=""
  local claude_model=""
  local claude_permission_mode=""
  local claude_effort=""
  local claude_timeout_seconds=""
  local claude_max_attempts=""
  local claude_retry_backoff_seconds=""
  local openclaw_model=""
  local openclaw_thinking=""
  local openclaw_timeout_seconds=""
  local ollama_model=""
  local ollama_base_url=""
  local ollama_timeout_seconds=""
  local pi_model=""
  local pi_thinking=""
  local pi_timeout_seconds=""
  local opencode_model=""
  local opencode_timeout_seconds=""
  local kilo_model=""
  local kilo_timeout_seconds=""

  backend="$(flow_provider_pool_backend "${config_file}" "${pool_name}")"
  safe_profile="$(flow_provider_pool_safe_profile "${config_file}" "${pool_name}")"
  bypass_profile="$(flow_provider_pool_bypass_profile "${config_file}" "${pool_name}")"
  claude_model="$(flow_provider_pool_claude_model "${config_file}" "${pool_name}")"
  claude_permission_mode="$(flow_provider_pool_claude_permission_mode "${config_file}" "${pool_name}")"
  claude_effort="$(flow_provider_pool_claude_effort "${config_file}" "${pool_name}")"
  claude_timeout_seconds="$(flow_provider_pool_claude_timeout_seconds "${config_file}" "${pool_name}")"
  claude_max_attempts="$(flow_provider_pool_claude_max_attempts "${config_file}" "${pool_name}")"
  claude_retry_backoff_seconds="$(flow_provider_pool_claude_retry_backoff_seconds "${config_file}" "${pool_name}")"
  openclaw_model="$(flow_provider_pool_openclaw_model "${config_file}" "${pool_name}")"
  openclaw_thinking="$(flow_provider_pool_openclaw_thinking "${config_file}" "${pool_name}")"
  openclaw_timeout_seconds="$(flow_provider_pool_openclaw_timeout_seconds "${config_file}" "${pool_name}")"
  ollama_model="$(flow_provider_pool_ollama_model "${config_file}" "${pool_name}")"
  ollama_base_url="$(flow_provider_pool_ollama_base_url "${config_file}" "${pool_name}")"
  ollama_timeout_seconds="$(flow_provider_pool_ollama_timeout_seconds "${config_file}" "${pool_name}")"
  pi_model="$(flow_provider_pool_pi_model "${config_file}" "${pool_name}")"
  pi_thinking="$(flow_provider_pool_pi_thinking "${config_file}" "${pool_name}")"
  pi_timeout_seconds="$(flow_provider_pool_pi_timeout_seconds "${config_file}" "${pool_name}")"
  opencode_model="$(flow_provider_pool_opencode_model "${config_file}" "${pool_name}")"
  opencode_timeout_seconds="$(flow_provider_pool_opencode_timeout_seconds "${config_file}" "${pool_name}")"
  kilo_model="$(flow_provider_pool_kilo_model "${config_file}" "${pool_name}")"
  kilo_timeout_seconds="$(flow_provider_pool_kilo_timeout_seconds "${config_file}" "${pool_name}")"
  model="$(flow_provider_pool_model_identity "${config_file}" "${pool_name}")"

  case "${backend}" in
    codex)
      [[ -n "${safe_profile}" && -n "${bypass_profile}" ]] || valid="no"
      ;;
    claude)
      [[ -n "${claude_model}" && -n "${claude_permission_mode}" && -n "${claude_effort}" && -n "${claude_timeout_seconds}" && -n "${claude_max_attempts}" && -n "${claude_retry_backoff_seconds}" ]] || valid="no"
      ;;
    openclaw)
      [[ -n "${openclaw_model}" && -n "${openclaw_thinking}" && -n "${openclaw_timeout_seconds}" ]] || valid="no"
      ;;
    ollama)
      [[ -n "${ollama_model}" ]] || valid="no"
      ;;
    pi)
      [[ -n "${pi_model}" ]] || valid="no"
      ;;
    opencode)
      [[ -n "${opencode_model}" && -n "${opencode_timeout_seconds}" ]] || valid="no"
      ;;
    kilo)
      [[ -n "${kilo_model}" && -n "${kilo_timeout_seconds}" ]] || valid="no"
      ;;
    *)
      valid="no"
      ;;
  esac

  if [[ "${valid}" == "yes" && -n "${model}" ]]; then
    state_root="$(flow_resolve_state_root "${config_file}")"
    provider_key="$(flow_sanitize_provider_key "${backend}-${model}")"
    state_file="${state_root}/retries/providers/${provider_key}.env"

    if [[ -f "${state_file}" ]]; then
      set -a
      # shellcheck source=/dev/null
      source "${state_file}"
      set +a
      attempts="${ATTEMPTS:-0}"
      next_attempt_epoch="${NEXT_ATTEMPT_EPOCH:-0}"
      next_attempt_at="${NEXT_ATTEMPT_AT:-}"
      last_reason="${LAST_REASON:-}"
      updated_at="${UPDATED_AT:-}"
    fi

    now_epoch="$(date +%s)"
    if [[ "${next_attempt_epoch}" =~ ^[0-9]+$ ]] && (( next_attempt_epoch > now_epoch )); then
      ready="no"
    fi
  else
    ready="no"
  fi

  printf 'POOL_NAME=%s\n' "${pool_name}"
  printf 'VALID=%s\n' "${valid}"
  printf 'BACKEND=%s\n' "${backend}"
  printf 'MODEL=%s\n' "${model}"
  printf 'PROVIDER_KEY=%s\n' "${provider_key}"
  printf 'ATTEMPTS=%s\n' "${attempts}"
  printf 'NEXT_ATTEMPT_EPOCH=%s\n' "${next_attempt_epoch}"
  printf 'NEXT_ATTEMPT_AT=%s\n' "${next_attempt_at}"
  printf 'READY=%s\n' "${ready}"
  printf 'LAST_REASON=%s\n' "${last_reason}"
  printf 'UPDATED_AT=%s\n' "${updated_at}"
  printf 'SAFE_PROFILE=%s\n' "${safe_profile}"
  printf 'BYPASS_PROFILE=%s\n' "${bypass_profile}"
  printf 'CLAUDE_MODEL=%s\n' "${claude_model}"
  printf 'CLAUDE_PERMISSION_MODE=%s\n' "${claude_permission_mode}"
  printf 'CLAUDE_EFFORT=%s\n' "${claude_effort}"
  printf 'CLAUDE_TIMEOUT_SECONDS=%s\n' "${claude_timeout_seconds}"
  printf 'CLAUDE_MAX_ATTEMPTS=%s\n' "${claude_max_attempts}"
  printf 'CLAUDE_RETRY_BACKOFF_SECONDS=%s\n' "${claude_retry_backoff_seconds}"
  printf 'OPENCLAW_MODEL=%s\n' "${openclaw_model}"
  printf 'OPENCLAW_THINKING=%s\n' "${openclaw_thinking}"
  printf 'OPENCLAW_TIMEOUT_SECONDS=%s\n' "${openclaw_timeout_seconds}"
  printf 'OLLAMA_MODEL=%s\n' "${ollama_model}"
  printf 'OLLAMA_BASE_URL=%s\n' "${ollama_base_url}"
  printf 'OLLAMA_TIMEOUT_SECONDS=%s\n' "${ollama_timeout_seconds}"
  printf 'PI_MODEL=%s\n' "${pi_model}"
  printf 'PI_THINKING=%s\n' "${pi_thinking}"
  printf 'PI_TIMEOUT_SECONDS=%s\n' "${pi_timeout_seconds}"
  printf 'OPENCODE_MODEL=%s\n' "${opencode_model}"
  printf 'OPENCODE_TIMEOUT_SECONDS=%s\n' "${opencode_timeout_seconds}"
  printf 'KILO_MODEL=%s\n' "${kilo_model}"
  printf 'KILO_TIMEOUT_SECONDS=%s\n' "${kilo_timeout_seconds}"
}

flow_selected_provider_pool_env() {
  local config_file="${1:-}"
  local pool_name=""
  local candidate=""
  local candidate_valid=""
  local candidate_ready=""
  local candidate_next_epoch="0"
  local exhausted_candidate=""
  local exhausted_epoch=""

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  if ! flow_provider_pools_enabled "${config_file}"; then
    return 1
  fi

  while IFS= read -r pool_name; do
    [[ -n "${pool_name}" ]] || continue
    candidate="$(flow_provider_pool_state_get "${config_file}" "${pool_name}")"
    candidate_valid="$(awk -F= '/^VALID=/{print $2}' <<<"${candidate}")"
    [[ "${candidate_valid}" == "yes" ]] || continue

    candidate_ready="$(awk -F= '/^READY=/{print $2}' <<<"${candidate}")"
    if [[ "${candidate_ready}" == "yes" ]]; then
      printf '%s\n' "${candidate}"
      printf 'POOLS_EXHAUSTED=no\n'
      printf 'SELECTION_REASON=ready\n'
      return 0
    fi

    candidate_next_epoch="$(awk -F= '/^NEXT_ATTEMPT_EPOCH=/{print $2}' <<<"${candidate}")"
    if [[ -z "${exhausted_candidate}" ]]; then
      exhausted_candidate="${candidate}"
      exhausted_epoch="${candidate_next_epoch}"
      continue
    fi

    if [[ "${candidate_next_epoch}" =~ ^[0-9]+$ && "${exhausted_epoch}" =~ ^[0-9]+$ ]] && (( candidate_next_epoch < exhausted_epoch )); then
      exhausted_candidate="${candidate}"
      exhausted_epoch="${candidate_next_epoch}"
    fi
  done < <(flow_provider_pool_names "${config_file}")

  [[ -n "${exhausted_candidate}" ]] || return 1

  printf '%s\n' "${exhausted_candidate}"
  printf 'POOLS_EXHAUSTED=yes\n'
  printf 'SELECTION_REASON=all-cooldown\n'
}

flow_resolve_issue_session_prefix() {
  local config_file="${1:-}"
  local default_value=""
  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi
  default_value="$(flow_default_issue_session_prefix "${config_file}")"
  flow_env_or_config "${config_file}" "ACP_ISSUE_SESSION_PREFIX F_LOSNING_ISSUE_SESSION_PREFIX" "session_naming.issue_prefix" "${default_value}"
}

flow_resolve_pr_session_prefix() {
  local config_file="${1:-}"
  local default_value=""
  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi
  default_value="$(flow_default_pr_session_prefix "${config_file}")"
  flow_env_or_config "${config_file}" "ACP_PR_SESSION_PREFIX F_LOSNING_PR_SESSION_PREFIX" "session_naming.pr_prefix" "${default_value}"
}

flow_resolve_issue_branch_prefix() {
  local config_file="${1:-}"
  local default_value=""
  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi
  default_value="$(flow_default_issue_branch_prefix "${config_file}")"
  flow_env_or_config "${config_file}" "ACP_ISSUE_BRANCH_PREFIX F_LOSNING_ISSUE_BRANCH_PREFIX" "session_naming.issue_branch_prefix" "${default_value}"
}

flow_resolve_pr_worktree_branch_prefix() {
  local config_file="${1:-}"
  local default_value=""
  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi
  default_value="$(flow_default_pr_worktree_branch_prefix "${config_file}")"
  flow_env_or_config "${config_file}" "ACP_PR_WORKTREE_BRANCH_PREFIX F_LOSNING_PR_WORKTREE_BRANCH_PREFIX" "session_naming.pr_worktree_branch_prefix" "${default_value}"
}

flow_resolve_managed_pr_branch_globs() {
  local config_file="${1:-}"
  local default_value=""
  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi
  default_value="$(flow_default_managed_pr_branch_globs "${config_file}")"
  flow_env_or_config "${config_file}" "ACP_MANAGED_PR_BRANCH_GLOBS F_LOSNING_MANAGED_PR_BRANCH_GLOBS" "session_naming.managed_pr_branch_globs" "${default_value}"
}

flow_escape_regex() {
  local raw_value="${1:-}"
  python3 - "${raw_value}" <<'PY'
import re
import sys

print(re.escape(sys.argv[1]))
PY
}

flow_managed_pr_prefixes() {
  local config_file="${1:-}"
  local managed_globs=""
  local branch_glob=""
  local prefix=""

  managed_globs="$(flow_resolve_managed_pr_branch_globs "${config_file}")"
  for branch_glob in ${managed_globs}; do
    prefix="${branch_glob%\*}"
    [[ -n "${prefix}" ]] || continue
    printf '%s\n' "${prefix}"
  done
}

flow_managed_pr_prefixes_json() {
  local config_file="${1:-}"
  local prefixes=()
  local prefix=""

  while IFS= read -r prefix; do
    [[ -n "${prefix}" ]] || continue
    prefixes+=("${prefix}")
  done < <(flow_managed_pr_prefixes "${config_file}")

  python3 - "${prefixes[@]}" <<'PY'
import json
import sys

print(json.dumps(sys.argv[1:]))
PY
}

flow_managed_issue_branch_regex() {
  local config_file="${1:-}"
  local prefix=""
  local normalized_prefix=""
  local escaped_prefix=""
  local joined=""

  while IFS= read -r prefix; do
    [[ -n "${prefix}" ]] || continue
    normalized_prefix="${prefix%/}"
    escaped_prefix="$(flow_escape_regex "${normalized_prefix}")"
    if [[ -n "${joined}" ]]; then
      joined="${joined}|${escaped_prefix}"
    else
      joined="${escaped_prefix}"
    fi
  done < <(flow_managed_pr_prefixes "${config_file}")

  if [[ -z "${joined}" ]]; then
    joined="$(flow_escape_regex "agent/$(flow_resolve_adapter_id "${config_file}")")"
  fi

  printf '^(?:%s)/issue-(?<id>[0-9]+)(?:-|$)\n' "${joined}"
}

flow_export_execution_env() {
  local config_file="${1:-}"

  if [[ -z "${config_file}" ]]; then
    config_file="$(resolve_flow_config_yaml "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")"
  fi

  [[ -f "${config_file}" ]] || return 0

  local repo_id=""
  local coding_worker=""
  local provider_quota_cooldowns=""
  local provider_pool_order=""
  local provider_pool_selection=""
  local explicit_coding_worker=""
  local active_provider_pool_name=""
  local active_provider_backend=""
  local active_provider_model=""
  local active_provider_key=""
  local active_provider_next_attempt_epoch=""
  local active_provider_next_attempt_at=""
  local active_provider_last_reason=""
  local active_provider_pools_exhausted="no"
  local active_provider_selection_reason="legacy-config"
  local safe_profile=""
  local bypass_profile=""
  local claude_model=""
  local claude_permission_mode=""
  local claude_effort=""
  local claude_timeout=""
  local claude_max_attempts=""
  local claude_retry_backoff_seconds=""
  local openclaw_model=""
  local openclaw_thinking=""
  local openclaw_timeout=""
  local openclaw_stall=""
  local ollama_model=""
  local ollama_base_url=""
  local ollama_timeout=""
  local pi_model=""
  local pi_thinking=""
  local pi_timeout=""
  local opencode_model=""
  local opencode_timeout=""
  local kilo_model=""
  local kilo_timeout=""

  repo_id="$(flow_resolve_repo_id "${config_file}")"
  provider_quota_cooldowns="$(flow_resolve_provider_quota_cooldowns "${config_file}")"
  provider_pool_order="$(flow_resolve_provider_pool_order "${config_file}")"
  explicit_coding_worker="${ACP_CODING_WORKER:-}"
  if [[ -z "${explicit_coding_worker}" && -n "${provider_pool_order}" ]]; then
    provider_pool_selection="$(flow_selected_provider_pool_env "${config_file}" || true)"
  fi

  if [[ -n "${provider_pool_selection}" ]]; then
    active_provider_pool_name="$(flow_kv_get "${provider_pool_selection}" "POOL_NAME")"
    active_provider_backend="$(flow_kv_get "${provider_pool_selection}" "BACKEND")"
    active_provider_model="$(flow_kv_get "${provider_pool_selection}" "MODEL")"
    active_provider_key="$(flow_kv_get "${provider_pool_selection}" "PROVIDER_KEY")"
    active_provider_next_attempt_epoch="$(flow_kv_get "${provider_pool_selection}" "NEXT_ATTEMPT_EPOCH")"
    active_provider_next_attempt_at="$(flow_kv_get "${provider_pool_selection}" "NEXT_ATTEMPT_AT")"
    active_provider_last_reason="$(flow_kv_get "${provider_pool_selection}" "LAST_REASON")"
    active_provider_pools_exhausted="$(flow_kv_get "${provider_pool_selection}" "POOLS_EXHAUSTED")"
    active_provider_selection_reason="$(flow_kv_get "${provider_pool_selection}" "SELECTION_REASON")"

    coding_worker="${active_provider_backend}"
    safe_profile="$(flow_kv_get "${provider_pool_selection}" "SAFE_PROFILE")"
    bypass_profile="$(flow_kv_get "${provider_pool_selection}" "BYPASS_PROFILE")"
    claude_model="$(flow_kv_get "${provider_pool_selection}" "CLAUDE_MODEL")"
    claude_permission_mode="$(flow_kv_get "${provider_pool_selection}" "CLAUDE_PERMISSION_MODE")"
    claude_effort="$(flow_kv_get "${provider_pool_selection}" "CLAUDE_EFFORT")"
    claude_timeout="$(flow_kv_get "${provider_pool_selection}" "CLAUDE_TIMEOUT_SECONDS")"
    claude_max_attempts="$(flow_kv_get "${provider_pool_selection}" "CLAUDE_MAX_ATTEMPTS")"
    claude_retry_backoff_seconds="$(flow_kv_get "${provider_pool_selection}" "CLAUDE_RETRY_BACKOFF_SECONDS")"
    openclaw_model="$(flow_kv_get "${provider_pool_selection}" "OPENCLAW_MODEL")"
    openclaw_thinking="$(flow_kv_get "${provider_pool_selection}" "OPENCLAW_THINKING")"
    openclaw_timeout="$(flow_kv_get "${provider_pool_selection}" "OPENCLAW_TIMEOUT_SECONDS")"
    openclaw_stall="$(flow_kv_get "${provider_pool_selection}" "OPENCLAW_STALL_SECONDS")"
    ollama_model="$(flow_kv_get "${provider_pool_selection}" "OLLAMA_MODEL")"
    ollama_base_url="$(flow_kv_get "${provider_pool_selection}" "OLLAMA_BASE_URL")"
    ollama_timeout="$(flow_kv_get "${provider_pool_selection}" "OLLAMA_TIMEOUT_SECONDS")"
    pi_model="$(flow_kv_get "${provider_pool_selection}" "PI_MODEL")"
    pi_thinking="$(flow_kv_get "${provider_pool_selection}" "PI_THINKING")"
    pi_timeout="$(flow_kv_get "${provider_pool_selection}" "PI_TIMEOUT_SECONDS")"
    opencode_model="$(flow_kv_get "${provider_pool_selection}" "OPENCODE_MODEL")"
    opencode_timeout="$(flow_kv_get "${provider_pool_selection}" "OPENCODE_TIMEOUT_SECONDS")"
    kilo_model="$(flow_kv_get "${provider_pool_selection}" "KILO_MODEL")"
    kilo_timeout="$(flow_kv_get "${provider_pool_selection}" "KILO_TIMEOUT_SECONDS")"
  else
    if [[ -n "${explicit_coding_worker}" ]]; then
      active_provider_selection_reason="env-override"
    fi
    coding_worker="$(flow_env_or_config "${config_file}" "ACP_CODING_WORKER" "execution.coding_worker" "")"
    safe_profile="$(flow_env_or_config "${config_file}" "ACP_CODEX_PROFILE_SAFE F_LOSNING_CODEX_PROFILE_SAFE" "execution.safe_profile" "")"
    bypass_profile="$(flow_env_or_config "${config_file}" "ACP_CODEX_PROFILE_BYPASS F_LOSNING_CODEX_PROFILE_BYPASS" "execution.bypass_profile" "")"
    claude_model="$(flow_env_or_config "${config_file}" "ACP_CLAUDE_MODEL F_LOSNING_CLAUDE_MODEL" "execution.claude.model" "")"
    claude_permission_mode="$(flow_env_or_config "${config_file}" "ACP_CLAUDE_PERMISSION_MODE F_LOSNING_CLAUDE_PERMISSION_MODE" "execution.claude.permission_mode" "")"
    claude_effort="$(flow_env_or_config "${config_file}" "ACP_CLAUDE_EFFORT F_LOSNING_CLAUDE_EFFORT" "execution.claude.effort" "")"
    claude_timeout="$(flow_env_or_config "${config_file}" "ACP_CLAUDE_TIMEOUT_SECONDS F_LOSNING_CLAUDE_TIMEOUT_SECONDS" "execution.claude.timeout_seconds" "")"
    claude_max_attempts="$(flow_env_or_config "${config_file}" "ACP_CLAUDE_MAX_ATTEMPTS F_LOSNING_CLAUDE_MAX_ATTEMPTS" "execution.claude.max_attempts" "")"
    claude_retry_backoff_seconds="$(flow_env_or_config "${config_file}" "ACP_CLAUDE_RETRY_BACKOFF_SECONDS F_LOSNING_CLAUDE_RETRY_BACKOFF_SECONDS" "execution.claude.retry_backoff_seconds" "")"
    openclaw_model="$(flow_env_or_config "${config_file}" "ACP_OPENCLAW_MODEL F_LOSNING_OPENCLAW_MODEL" "execution.openclaw.model" "")"
    openclaw_thinking="$(flow_env_or_config "${config_file}" "ACP_OPENCLAW_THINKING F_LOSNING_OPENCLAW_THINKING" "execution.openclaw.thinking" "")"
    openclaw_timeout="$(flow_env_or_config "${config_file}" "ACP_OPENCLAW_TIMEOUT_SECONDS F_LOSNING_OPENCLAW_TIMEOUT_SECONDS" "execution.openclaw.timeout_seconds" "")"
    openclaw_stall="$(flow_env_or_config "${config_file}" "ACP_OPENCLAW_STALL_SECONDS F_LOSNING_OPENCLAW_STALL_SECONDS" "execution.openclaw.stall_seconds" "")"
    ollama_model="$(flow_env_or_config "${config_file}" "ACP_OLLAMA_MODEL F_LOSNING_OLLAMA_MODEL" "execution.ollama.model" "")"
    ollama_base_url="$(flow_env_or_config "${config_file}" "ACP_OLLAMA_BASE_URL F_LOSNING_OLLAMA_BASE_URL" "execution.ollama.base_url" "")"
    ollama_timeout="$(flow_env_or_config "${config_file}" "ACP_OLLAMA_TIMEOUT_SECONDS F_LOSNING_OLLAMA_TIMEOUT_SECONDS" "execution.ollama.timeout_seconds" "")"
    pi_model="$(flow_env_or_config "${config_file}" "ACP_PI_MODEL F_LOSNING_PI_MODEL" "execution.pi.model" "")"
    pi_thinking="$(flow_env_or_config "${config_file}" "ACP_PI_THINKING F_LOSNING_PI_THINKING" "execution.pi.thinking" "")"
    pi_timeout="$(flow_env_or_config "${config_file}" "ACP_PI_TIMEOUT_SECONDS F_LOSNING_PI_TIMEOUT_SECONDS" "execution.pi.timeout_seconds" "")"
    opencode_model="$(flow_env_or_config "${config_file}" "ACP_OPENCODE_MODEL F_LOSNING_OPENCODE_MODEL" "execution.opencode.model" "")"
    opencode_timeout="$(flow_env_or_config "${config_file}" "ACP_OPENCODE_TIMEOUT_SECONDS F_LOSNING_OPENCODE_TIMEOUT_SECONDS" "execution.opencode.timeout_seconds" "")"
    kilo_model="$(flow_env_or_config "${config_file}" "ACP_KILO_MODEL F_LOSNING_KILO_MODEL" "execution.kilo.model" "")"
    kilo_timeout="$(flow_env_or_config "${config_file}" "ACP_KILO_TIMEOUT_SECONDS F_LOSNING_KILO_TIMEOUT_SECONDS" "execution.kilo.timeout_seconds" "")"
  fi

  if [[ -n "${coding_worker}" ]]; then
    export ACP_CODING_WORKER="${coding_worker}"
  fi
  if [[ -n "${repo_id}" ]]; then
    export F_LOSNING_REPO_ID="${repo_id}"
    export ACP_REPO_ID="${repo_id}"
    export F_LOSNING_GITHUB_REPOSITORY_ID="${repo_id}"
    export ACP_GITHUB_REPOSITORY_ID="${repo_id}"
  fi
  if [[ -n "${provider_quota_cooldowns}" ]]; then
    export F_LOSNING_PROVIDER_QUOTA_COOLDOWNS="${provider_quota_cooldowns}"
    export ACP_PROVIDER_QUOTA_COOLDOWNS="${provider_quota_cooldowns}"
  fi
  export F_LOSNING_PROVIDER_POOL_ORDER="${provider_pool_order}"
  export ACP_PROVIDER_POOL_ORDER="${provider_pool_order}"
  export F_LOSNING_ACTIVE_PROVIDER_POOL_NAME="${active_provider_pool_name}"
  export ACP_ACTIVE_PROVIDER_POOL_NAME="${active_provider_pool_name}"
  export F_LOSNING_ACTIVE_PROVIDER_BACKEND="${active_provider_backend}"
  export ACP_ACTIVE_PROVIDER_BACKEND="${active_provider_backend}"
  export F_LOSNING_ACTIVE_PROVIDER_MODEL="${active_provider_model}"
  export ACP_ACTIVE_PROVIDER_MODEL="${active_provider_model}"
  export F_LOSNING_ACTIVE_PROVIDER_KEY="${active_provider_key}"
  export ACP_ACTIVE_PROVIDER_KEY="${active_provider_key}"
  export F_LOSNING_PROVIDER_POOLS_EXHAUSTED="${active_provider_pools_exhausted}"
  export ACP_PROVIDER_POOLS_EXHAUSTED="${active_provider_pools_exhausted}"
  export F_LOSNING_PROVIDER_POOL_SELECTION_REASON="${active_provider_selection_reason}"
  export ACP_PROVIDER_POOL_SELECTION_REASON="${active_provider_selection_reason}"
  export F_LOSNING_PROVIDER_POOL_NEXT_ATTEMPT_EPOCH="${active_provider_next_attempt_epoch}"
  export ACP_PROVIDER_POOL_NEXT_ATTEMPT_EPOCH="${active_provider_next_attempt_epoch}"
  export F_LOSNING_PROVIDER_POOL_NEXT_ATTEMPT_AT="${active_provider_next_attempt_at}"
  export ACP_PROVIDER_POOL_NEXT_ATTEMPT_AT="${active_provider_next_attempt_at}"
  export F_LOSNING_PROVIDER_POOL_LAST_REASON="${active_provider_last_reason}"
  export ACP_PROVIDER_POOL_LAST_REASON="${active_provider_last_reason}"
  if [[ -n "${safe_profile}" ]]; then
    export F_LOSNING_CODEX_PROFILE_SAFE="${safe_profile}"
    export ACP_CODEX_PROFILE_SAFE="${safe_profile}"
  fi
  if [[ -n "${bypass_profile}" ]]; then
    export F_LOSNING_CODEX_PROFILE_BYPASS="${bypass_profile}"
    export ACP_CODEX_PROFILE_BYPASS="${bypass_profile}"
  fi
  if [[ -n "${claude_model}" ]]; then
    export F_LOSNING_CLAUDE_MODEL="${claude_model}"
    export ACP_CLAUDE_MODEL="${claude_model}"
  fi
  if [[ -n "${claude_permission_mode}" ]]; then
    export F_LOSNING_CLAUDE_PERMISSION_MODE="${claude_permission_mode}"
    export ACP_CLAUDE_PERMISSION_MODE="${claude_permission_mode}"
  fi
  if [[ -n "${claude_effort}" ]]; then
    export F_LOSNING_CLAUDE_EFFORT="${claude_effort}"
    export ACP_CLAUDE_EFFORT="${claude_effort}"
  fi
  if [[ -n "${claude_timeout}" ]]; then
    export F_LOSNING_CLAUDE_TIMEOUT_SECONDS="${claude_timeout}"
    export ACP_CLAUDE_TIMEOUT_SECONDS="${claude_timeout}"
  fi
  if [[ -n "${claude_max_attempts}" ]]; then
    export F_LOSNING_CLAUDE_MAX_ATTEMPTS="${claude_max_attempts}"
    export ACP_CLAUDE_MAX_ATTEMPTS="${claude_max_attempts}"
  fi
  if [[ -n "${claude_retry_backoff_seconds}" ]]; then
    export F_LOSNING_CLAUDE_RETRY_BACKOFF_SECONDS="${claude_retry_backoff_seconds}"
    export ACP_CLAUDE_RETRY_BACKOFF_SECONDS="${claude_retry_backoff_seconds}"
  fi
  if [[ -n "${openclaw_model}" ]]; then
    export F_LOSNING_OPENCLAW_MODEL="${openclaw_model}"
    export ACP_OPENCLAW_MODEL="${openclaw_model}"
  fi
  if [[ -n "${openclaw_thinking}" ]]; then
    export F_LOSNING_OPENCLAW_THINKING="${openclaw_thinking}"
    export ACP_OPENCLAW_THINKING="${openclaw_thinking}"
  fi
  if [[ -n "${openclaw_timeout}" ]]; then
    export F_LOSNING_OPENCLAW_TIMEOUT_SECONDS="${openclaw_timeout}"
    export ACP_OPENCLAW_TIMEOUT_SECONDS="${openclaw_timeout}"
  fi
  if [[ -n "${openclaw_stall}" ]]; then
    export F_LOSNING_OPENCLAW_STALL_SECONDS="${openclaw_stall}"
    export ACP_OPENCLAW_STALL_SECONDS="${openclaw_stall}"
  fi
  if [[ -n "${ollama_model}" ]]; then
    export F_LOSNING_OLLAMA_MODEL="${ollama_model}"
    export ACP_OLLAMA_MODEL="${ollama_model}"
  fi
  if [[ -n "${ollama_base_url}" ]]; then
    export F_LOSNING_OLLAMA_BASE_URL="${ollama_base_url}"
    export ACP_OLLAMA_BASE_URL="${ollama_base_url}"
  fi
  if [[ -n "${ollama_timeout}" ]]; then
    export F_LOSNING_OLLAMA_TIMEOUT_SECONDS="${ollama_timeout}"
    export ACP_OLLAMA_TIMEOUT_SECONDS="${ollama_timeout}"
  fi
  if [[ -n "${pi_model}" ]]; then
    export F_LOSNING_PI_MODEL="${pi_model}"
    export ACP_PI_MODEL="${pi_model}"
  fi
  if [[ -n "${pi_thinking}" ]]; then
    export F_LOSNING_PI_THINKING="${pi_thinking}"
    export ACP_PI_THINKING="${pi_thinking}"
  fi
  if [[ -n "${pi_timeout}" ]]; then
    export F_LOSNING_PI_TIMEOUT_SECONDS="${pi_timeout}"
    export ACP_PI_TIMEOUT_SECONDS="${pi_timeout}"
  fi
  if [[ -n "${opencode_model}" ]]; then
    export F_LOSNING_OPENCODE_MODEL="${opencode_model}"
    export ACP_OPENCODE_MODEL="${opencode_model}"
  fi
  if [[ -n "${opencode_timeout}" ]]; then
    export F_LOSNING_OPENCODE_TIMEOUT_SECONDS="${opencode_timeout}"
    export ACP_OPENCODE_TIMEOUT_SECONDS="${opencode_timeout}"
  fi
  if [[ -n "${kilo_model}" ]]; then
    export F_LOSNING_KILO_MODEL="${kilo_model}"
    export ACP_KILO_MODEL="${kilo_model}"
  fi
  if [[ -n "${kilo_timeout}" ]]; then
    export F_LOSNING_KILO_TIMEOUT_SECONDS="${kilo_timeout}"
    export ACP_KILO_TIMEOUT_SECONDS="${kilo_timeout}"
  fi

  flow_export_github_cli_auth_env "$(flow_resolve_repo_slug "${config_file}")"
  flow_export_project_env_aliases
}
