#!/usr/bin/env bash
set -euo pipefail

SESSION="${1:?usage: label-follow-up-issues.sh SESSION}"
ADAPTER_BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLOW_SKILL_DIR="$(cd "${ADAPTER_BIN_DIR}/.." && pwd)"
FLOW_TOOLS_DIR="${FLOW_SKILL_DIR}/tools/bin"
# shellcheck source=/dev/null
source "${FLOW_TOOLS_DIR}/flow-config-lib.sh"
CONFIG_YAML="$(resolve_flow_config_yaml "${BASH_SOURCE[0]}")"
flow_export_execution_env "${CONFIG_YAML}"
flow_export_project_env_aliases
REPO_SLUG="$(flow_resolve_repo_slug "${CONFIG_YAML}")"
AGENT_ROOT="$(flow_resolve_agent_root "${CONFIG_YAML}")"
RUNS_ROOT="$(flow_resolve_runs_root "${CONFIG_YAML}")"
HISTORY_ROOT="$(flow_resolve_history_root "${CONFIG_YAML}")"

find_archived_session_dir() {
  local root="${1:-}"
  local target_session="${2:-}"
  [[ -n "$root" && -d "$root" && -n "$target_session" ]] || return 1

  find "$root" -mindepth 1 -maxdepth 1 -type d -name "${target_session}-*" ! -name "${target_session}-stale-*" 2>/dev/null \
    | sort -r \
    | head -n 1
}

status_out="$(
  bash "${FLOW_TOOLS_DIR}/agent-project-worker-status" \
    --runs-root "$RUNS_ROOT" \
    --session "$SESSION"
)"
meta_file="$(awk -F= '/^META_FILE=/{print $2}' <<<"$status_out")"
if [[ -z "$meta_file" || ! -f "$meta_file" ]]; then
  archived_run_dir="$(find_archived_session_dir "$HISTORY_ROOT" "$SESSION" || true)"
  if [[ -n "$archived_run_dir" && -f "${archived_run_dir}/run.env" ]]; then
    meta_file="${archived_run_dir}/run.env"
  fi
fi
if [[ -z "$meta_file" || ! -f "$meta_file" ]]; then
  echo "missing metadata for session $SESSION" >&2
  exit 1
fi

set -a
# shellcheck source=/dev/null
source "$meta_file"
set +a

if [[ -z "${ISSUE_ID:-}" ]]; then
  echo "session $SESSION is missing ISSUE_ID" >&2
  exit 1
fi
if [[ -z "${STARTED_AT:-}" ]]; then
  echo "session $SESSION is missing STARTED_AT" >&2
  exit 1
fi

actor_login="${GITHUB_ACTOR:-$(gh api user --jq .login)}"

issue_numbers=()
while IFS= read -r number; do
  [[ -n "$number" ]] || continue
  issue_numbers+=("$number")
done < <(
  flow_github_api_repo "${REPO_SLUG}" "issues/${ISSUE_ID}/comments?per_page=100" --paginate --slurp 2>/dev/null \
    | jq -r --arg actor "$actor_login" --arg started "$STARTED_AT" '
        .[]?
        | if type == "array" then .[] else . end
        | select(.user.login == $actor)
        | select(.created_at >= $started)
        | .body // ""
      ' \
    | rg -o '#[0-9]+' \
    | tr -d '#' \
    | sort -n \
    | uniq
)

count=0
if [[ ${#issue_numbers[@]} -eq 0 ]]; then
  printf 'COUNT=%s\n' "$count"
  exit 0
fi

for number in "${issue_numbers[@]}"; do
  [[ "$number" == "$ISSUE_ID" ]] && continue

  issue_json="$(flow_github_issue_view_json "${REPO_SLUG}" "${number}" 2>/dev/null || true)"
  [[ -z "$issue_json" ]] && continue

  if jq -e 'has("pull_request")' >/dev/null <<<"$issue_json"; then
    continue
  fi

  state="$(jq -r '.state // "" | ascii_downcase' <<<"$issue_json")"
  [[ "$state" == "open" ]] || continue

  if jq -e 'any(.labels[]?; .name == "agent-running" or .name == "agent-blocked")' >/dev/null <<<"$issue_json"; then
    continue
  fi

  class_out="$("${ADAPTER_BIN_DIR}/issue-resource-class.sh" "$number")"
  is_e2e="$(awk -F= '/^IS_E2E=/{print $2}' <<<"$class_out")"

  if [[ "$is_e2e" == "yes" ]]; then
    bash "${FLOW_TOOLS_DIR}/agent-github-update-labels" --repo-slug "$REPO_SLUG" --number "$number" --add agent-e2e-heavy >/dev/null
  fi

  printf 'LABELED=%s\n' "$number"
  count=$((count + 1))
done

printf 'COUNT=%s\n' "$count"
