#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-config-lib.sh"

usage() {
  cat <<'EOF'
Usage:
  github-write-outbox.sh enqueue-labels --repo-slug <owner/repo> --number <id> [--add LABEL]... [--remove LABEL]...
  github-write-outbox.sh enqueue-comment --repo-slug <owner/repo> --number <id> --kind issue|pr --body-file <path>
  github-write-outbox.sh enqueue-approval --repo-slug <owner/repo> --number <id> [--body <text>]
  github-write-outbox.sh flush [--limit <n>]

Persist GitHub write intents locally so ACP can continue operating while GitHub
is unavailable or rate-limited.
EOF
}

CONFIG_YAML="$(resolve_flow_config_yaml "${BASH_SOURCE[0]}")"
STATE_ROOT="$(flow_resolve_state_root "${CONFIG_YAML}")"
OUTBOX_ROOT="${ACP_GITHUB_OUTBOX_ROOT:-${STATE_ROOT}/github-outbox}"
PENDING_DIR="${OUTBOX_ROOT}/pending"
SENT_DIR="${OUTBOX_ROOT}/sent"
FAILED_DIR="${OUTBOX_ROOT}/failed"
PYTHON_BIN="$(flow_resolve_python_bin || true)"
ACTION="${1:-}"
DEFAULT_APPROVAL_BODY="Automated final review passed. Safe low-risk scope, green checks, and host-side merge approved."

mkdir -p "${PENDING_DIR}" "${SENT_DIR}" "${FAILED_DIR}"

json_hash() {
  local payload="${1:-}"

  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "${payload}" | shasum -a 256 | awk '{print $1}'
    return 0
  fi

  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "${payload}" | sha256sum | awk '{print $1}'
    return 0
  fi

  if [[ -n "${PYTHON_BIN:-}" ]]; then
    PAYLOAD="${payload}" "${PYTHON_BIN}" - <<'PY'
import hashlib
import os

print(hashlib.sha256((os.environ.get("PAYLOAD", "")).encode("utf-8")).hexdigest())
PY
    return 0
  fi

  return 1
}

outbox_move_sent() {
  local intent_file="${1:?intent file required}"
  mv "${intent_file}" "${SENT_DIR}/$(basename "${intent_file}")"
}

outbox_move_failed() {
  local intent_file="${1:?intent file required}"
  mv "${intent_file}" "${FAILED_DIR}/$(basename "${intent_file}")"
}

enqueue_labels() {
  local repo_slug=""
  local number=""
  local add_file=""
  local remove_file=""
  local add_json="[]"
  local remove_json="[]"
  local created_at=""
  local payload=""
  local digest=""
  local intent_file=""

  add_file="$(mktemp)"
  remove_file="$(mktemp)"
  trap 'rm -f "${add_file}" "${remove_file}"' RETURN

  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo-slug) repo_slug="${2:-}"; shift 2 ;;
      --number) number="${2:-}"; shift 2 ;;
      --add)
        printf '%s\n' "${2:?missing label after --add}" >>"${add_file}"
        shift 2
        ;;
      --remove)
        printf '%s\n' "${2:?missing label after --remove}" >>"${remove_file}"
        shift 2
        ;;
      --help|-h) usage; exit 0 ;;
      *)
        echo "unknown argument: $1" >&2
        exit 1
        ;;
    esac
  done

  [[ -n "${repo_slug}" && -n "${number}" ]] || {
    usage >&2
    exit 1
  }

  add_json="$(jq -R . <"${add_file}" | jq -s 'map(select(length > 0)) | unique')"
  remove_json="$(jq -R . <"${remove_file}" | jq -s 'map(select(length > 0)) | unique')"
  created_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  payload="$(
    jq -cn \
      --arg type "labels" \
      --arg repo_slug "${repo_slug}" \
      --arg number "${number}" \
      --arg created_at "${created_at}" \
      --argjson add "${add_json}" \
      --argjson remove "${remove_json}" \
      '{
        type: $type,
        repo_slug: $repo_slug,
        number: $number,
        created_at: $created_at,
        add: $add,
        remove: $remove
      }'
  )"
  digest="$(json_hash "${payload}")"
  intent_file="${PENDING_DIR}/labels-${number}-${digest}.json"
  if [[ ! -f "${intent_file}" ]]; then
    printf '%s\n' "${payload}" >"${intent_file}"
  fi
  printf 'OUTBOX_FILE=%s\n' "${intent_file}"
}

enqueue_comment() {
  local repo_slug=""
  local number=""
  local kind=""
  local body_file=""
  local body=""
  local body_sha=""
  local created_at=""
  local payload=""
  local intent_file=""

  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo-slug) repo_slug="${2:-}"; shift 2 ;;
      --number) number="${2:-}"; shift 2 ;;
      --kind) kind="${2:-}"; shift 2 ;;
      --body-file) body_file="${2:-}"; shift 2 ;;
      --help|-h) usage; exit 0 ;;
      *)
        echo "unknown argument: $1" >&2
        exit 1
        ;;
    esac
  done

  [[ -n "${repo_slug}" && -n "${number}" && -n "${kind}" && -n "${body_file}" ]] || {
    usage >&2
    exit 1
  }
  [[ "${kind}" == "issue" || "${kind}" == "pr" ]] || {
    echo "unsupported comment kind: ${kind}" >&2
    exit 1
  }
  [[ -f "${body_file}" ]] || {
    echo "missing comment body file: ${body_file}" >&2
    exit 1
  }

  body="$(cat "${body_file}")"
  [[ -n "${body}" ]] || {
    echo "empty comment body" >&2
    exit 1
  }

  body_sha="$(json_hash "${body}")"
  created_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  payload="$(
    jq -cn \
      --arg type "comment" \
      --arg repo_slug "${repo_slug}" \
      --arg number "${number}" \
      --arg kind "${kind}" \
      --arg body "${body}" \
      --arg body_sha "${body_sha}" \
      --arg created_at "${created_at}" \
      '{
        type: $type,
        repo_slug: $repo_slug,
        number: $number,
        kind: $kind,
        body: $body,
        body_sha: $body_sha,
        created_at: $created_at
      }'
  )"
  intent_file="${PENDING_DIR}/comment-${kind}-${number}-${body_sha}.json"
  if [[ ! -f "${intent_file}" ]]; then
    printf '%s\n' "${payload}" >"${intent_file}"
  fi
  printf 'OUTBOX_FILE=%s\n' "${intent_file}"
}

enqueue_approval() {
  local repo_slug=""
  local number=""
  local body="${DEFAULT_APPROVAL_BODY}"
  local body_sha=""
  local created_at=""
  local payload=""
  local intent_file=""

  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo-slug) repo_slug="${2:-}"; shift 2 ;;
      --number) number="${2:-}"; shift 2 ;;
      --body) body="${2:-}"; shift 2 ;;
      --help|-h) usage; exit 0 ;;
      *)
        echo "unknown argument: $1" >&2
        exit 1
        ;;
    esac
  done

  [[ -n "${repo_slug}" && -n "${number}" && -n "${body}" ]] || {
    usage >&2
    exit 1
  }

  body_sha="$(json_hash "${body}")"
  created_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  payload="$(
    jq -cn \
      --arg type "approval" \
      --arg repo_slug "${repo_slug}" \
      --arg number "${number}" \
      --arg body "${body}" \
      --arg body_sha "${body_sha}" \
      --arg created_at "${created_at}" \
      '{
        type: $type,
        repo_slug: $repo_slug,
        number: $number,
        body: $body,
        body_sha: $body_sha,
        created_at: $created_at
      }'
  )"
  intent_file="${PENDING_DIR}/approval-${number}-${body_sha}.json"
  if [[ ! -f "${intent_file}" ]]; then
    printf '%s\n' "${payload}" >"${intent_file}"
  fi
  printf 'OUTBOX_FILE=%s\n' "${intent_file}"
}

flush_comment_intent() {
  local intent_file="${1:?intent file required}"
  local repo_slug=""
  local number=""
  local kind=""
  local body=""
  local existing_json=""
  local post_payload=""

  repo_slug="$(jq -r '.repo_slug // ""' "${intent_file}")"
  number="$(jq -r '.number // ""' "${intent_file}")"
  kind="$(jq -r '.kind // ""' "${intent_file}")"
  body="$(jq -r '.body // ""' "${intent_file}")"

  [[ -n "${repo_slug}" && -n "${number}" && -n "${kind}" && -n "${body}" ]] || return 65

  if [[ "${kind}" == "pr" ]]; then
    existing_json="$(flow_github_pr_view_json "${repo_slug}" "${number}" 2>/dev/null || true)"
  else
    existing_json="$(flow_github_issue_view_json "${repo_slug}" "${number}" 2>/dev/null || true)"
  fi

  if [[ -n "${existing_json}" ]] && jq -e --arg body "${body}" 'any(.comments[]?; .body == $body)' >/dev/null <<<"${existing_json}" 2>/dev/null; then
    return 0
  fi

  post_payload="$(jq -cn --arg body "${body}" '{body: $body}')"
  if printf '%s' "${post_payload}" | flow_github_api_repo "${repo_slug}" "issues/${number}/comments" --method POST --input - >/dev/null 2>&1; then
    return 0
  fi

  if flow_github_core_rate_limit_active; then
    return 75
  fi

  return 1
}

flush_labels_intent() {
  local intent_file="${1:?intent file required}"
  local repo_slug=""
  local number=""
  local -a args=()
  local label=""

  repo_slug="$(jq -r '.repo_slug // ""' "${intent_file}")"
  number="$(jq -r '.number // ""' "${intent_file}")"
  [[ -n "${repo_slug}" && -n "${number}" ]] || return 65

  args=(--repo-slug "${repo_slug}" --number "${number}")
  while IFS= read -r label; do
    [[ -n "${label}" ]] || continue
    args+=(--add "${label}")
  done < <(jq -r '.add[]? // empty' "${intent_file}")
  while IFS= read -r label; do
    [[ -n "${label}" ]] || continue
    args+=(--remove "${label}")
  done < <(jq -r '.remove[]? // empty' "${intent_file}")

  if ACP_GITHUB_OUTBOX_DISABLE_ENQUEUE=1 bash "${SCRIPT_DIR}/agent-github-update-labels" "${args[@]}" >/dev/null 2>&1; then
    return 0
  fi

  if flow_github_core_rate_limit_active; then
    return 75
  fi

  return 1
}

flush_approval_intent() {
  local intent_file="${1:?intent file required}"
  local repo_slug=""
  local number=""
  local body=""
  local reviews_json="[]"
  local post_payload=""

  repo_slug="$(jq -r '.repo_slug // ""' "${intent_file}")"
  number="$(jq -r '.number // ""' "${intent_file}")"
  body="$(jq -r '.body // ""' "${intent_file}")"

  [[ -n "${repo_slug}" && -n "${number}" && -n "${body}" ]] || return 65

  if reviews_json="$(flow_github_api_repo "${repo_slug}" "pulls/${number}/reviews?per_page=100" 2>/dev/null)"; then
    reviews_json="$(flow_json_or_default "${reviews_json}" '[]')"
    if jq -e --arg body "${body}" 'any(.[]?; (.state // "") == "APPROVED" and (.body // "") == $body)' >/dev/null <<<"${reviews_json}" 2>/dev/null; then
      return 0
    fi
  elif flow_github_core_rate_limit_active; then
    return 75
  fi

  post_payload="$(jq -cn --arg event "APPROVE" --arg body "${body}" '{event: $event, body: $body}')"
  if printf '%s' "${post_payload}" | flow_github_api_repo "${repo_slug}" "pulls/${number}/reviews" --method POST --input - >/dev/null 2>&1; then
    return 0
  fi

  if flow_github_core_rate_limit_active; then
    return 75
  fi

  return 1
}

flush_outbox() {
  local limit="25"
  local processed="0"
  local intent_file=""
  local intent_type=""
  local status="0"

  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --limit) limit="${2:-25}"; shift 2 ;;
      --help|-h) usage; exit 0 ;;
      *)
        echo "unknown argument: $1" >&2
        exit 1
        ;;
    esac
  done

  [[ -d "${PENDING_DIR}" ]] || exit 0
  flow_github_core_rate_limit_active && exit 0

  while IFS= read -r intent_file; do
    [[ -n "${intent_file}" ]] || continue
    if (( processed >= limit )); then
      break
    fi

    intent_type="$(jq -r '.type // ""' "${intent_file}" 2>/dev/null || true)"
    case "${intent_type}" in
      labels)
        if flush_labels_intent "${intent_file}"; then
          status="0"
        else
          status="$?"
        fi
        ;;
      comment)
        if flush_comment_intent "${intent_file}"; then
          status="0"
        else
          status="$?"
        fi
        ;;
      approval)
        if flush_approval_intent "${intent_file}"; then
          status="0"
        else
          status="$?"
        fi
        ;;
      *)
        status="65"
        ;;
    esac

    case "${status}" in
      0)
        outbox_move_sent "${intent_file}"
        ;;
      65)
        outbox_move_failed "${intent_file}"
        ;;
      75)
        break
        ;;
      *)
        break
        ;;
    esac

    processed=$((processed + 1))
  done < <(find "${PENDING_DIR}" -mindepth 1 -maxdepth 1 -type f -name '*.json' 2>/dev/null | sort)

  printf 'OUTBOX_FLUSHED=%s\n' "${processed}"
}

case "${ACTION}" in
  enqueue-labels)
    enqueue_labels "$@"
    ;;
  enqueue-comment)
    enqueue_comment "$@"
    ;;
  enqueue-approval)
    enqueue_approval "$@"
    ;;
  flush)
    flush_outbox "$@"
    ;;
  --help|-h|"")
    usage
    exit 0
    ;;
  *)
    echo "unknown action: ${ACTION}" >&2
    usage >&2
    exit 1
    ;;
esac
