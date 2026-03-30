#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-config-lib.sh"

usage() {
  cat <<'EOF'
Usage:
  create-follow-up-issue.sh --parent ISSUE_ID --title "Title" [--body "text" | --body-file path] [--label LABEL ...]

Create a focused follow-up issue linked back to the umbrella issue. By default the
new issue is left unlabeled so the scheduler can pick it up normally.
EOF
}

FLOW_TOOLS_DIR="${SCRIPT_DIR}"
CONFIG_YAML="$(resolve_flow_config_yaml "${BASH_SOURCE[0]}")"
REPO_SLUG="$(flow_resolve_repo_slug "${CONFIG_YAML}")"
UPDATE_LABELS_BIN="${UPDATE_LABELS_BIN:-${FLOW_TOOLS_DIR}/agent-github-update-labels}"

parent_issue=""
title=""
body=""
body_file=""
labels=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --parent)
      parent_issue="${2:-}"
      shift 2
      ;;
    --title)
      title="${2:-}"
      shift 2
      ;;
    --body)
      body="${2:-}"
      shift 2
      ;;
    --body-file)
      body_file="${2:-}"
      shift 2
      ;;
    --label)
      labels+=("${2:-}")
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$parent_issue" || -z "$title" ]]; then
  usage >&2
  exit 1
fi

if [[ -n "$body" && -n "$body_file" ]]; then
  echo "Provide either --body or --body-file, not both." >&2
  exit 1
fi

tmp_body_file="$(mktemp)"
cleanup() {
  rm -f "$tmp_body_file"
}
trap cleanup EXIT

{
  printf 'Parent issue: #%s\n\n' "$parent_issue"
  if [[ -n "$body_file" ]]; then
    cat "$body_file"
  elif [[ -n "$body" ]]; then
    printf '%s\n' "$body"
  else
    printf 'Follow-up slice decomposed from umbrella issue #%s.\n' "$parent_issue"
  fi
} >"$tmp_body_file"

issue_url="$(flow_github_issue_create "$REPO_SLUG" "$title" "$tmp_body_file")"
issue_url="$(printf '%s' "$issue_url" | tail -n 1)"
issue_number="$(sed -nE 's#.*/issues/([0-9]+)$#\1#p' <<<"$issue_url" | tail -n 1)"

if [[ -z "$issue_number" ]]; then
  echo "Unable to determine created issue number from gh output: $issue_url" >&2
  exit 1
fi

if [[ ${#labels[@]} -gt 0 ]]; then
  update_args=()
  for label in "${labels[@]}"; do
    [[ -n "$label" ]] || continue
    update_args+=(--add "$label")
  done
  if [[ ${#update_args[@]} -gt 0 ]]; then
    bash "${UPDATE_LABELS_BIN}" \
      --repo-slug "$REPO_SLUG" \
      --number "$issue_number" \
      "${update_args[@]}" >/dev/null || true
  fi
fi

printf 'ISSUE_NUMBER=%s\n' "$issue_number"
printf 'ISSUE_URL=%s\n' "$issue_url"
