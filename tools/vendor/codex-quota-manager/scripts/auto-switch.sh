#!/usr/bin/env bash
set -euo pipefail

# Load NVM for Node.js (required for codex-quota in agent environments).
export NVM_DIR="$HOME/.nvm"
if [[ -s "$NVM_DIR/nvm.sh" ]]; then
  # shellcheck source=/dev/null
  . "$NVM_DIR/nvm.sh"
  if command -v node >/dev/null 2>&1; then
    NODE_BIN="$(dirname "$(command -v node)")"
    export PATH="$NODE_BIN:$PATH"
  fi
fi

FIVE_HOUR_THRESHOLD="${CODEX_QUOTA_MANAGER_FIVE_HOUR_THRESHOLD:-70}"
WEEKLY_THRESHOLD="${CODEX_QUOTA_MANAGER_WEEKLY_THRESHOLD:-90}"
RUNNING_WORKERS="${CODEX_QUOTA_MANAGER_RUNNING_WORKERS:-0}"
ACTIVE_QUOTA_TIMEOUT_SECONDS="${CODEX_QUOTA_MANAGER_ACTIVE_TIMEOUT_SECONDS:-20}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/codex-quota-manager"
STATE_FILE="${CODEX_QUOTA_MANAGER_STATE_FILE:-${CACHE_DIR}/rotation-state.json}"
SWITCH_STATE_FILE="${CODEX_QUOTA_MANAGER_SWITCH_STATE_FILE:-${CACHE_DIR}/last-switch.env}"
TRIGGER_REASON="usage-limit"
CURRENT_LABEL=""
PREFER_LABEL=""
CODEX_QUOTA_BIN="${CODEX_QUOTA_BIN:-$(command -v codex-quota 2>/dev/null || true)}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) shift 2 ;; # legacy no-op; scheduler no longer uses preflight scanning
    --trigger-reason) TRIGGER_REASON="${2:-}"; shift 2 ;;
    --current-label) CURRENT_LABEL="${2:-}"; shift 2 ;;
    --threshold|--five-hour-threshold) FIVE_HOUR_THRESHOLD="${2:-}"; shift 2 ;;
    --weekly-threshold) WEEKLY_THRESHOLD="${2:-}"; shift 2 ;;
    --running-workers) RUNNING_WORKERS="${2:-}"; shift 2 ;;
    --prefer-label) PREFER_LABEL="${2:-}"; shift 2 ;;
    --soft-five-hour-threshold|--soft-worker-threshold|--emergency-five-hour-threshold|--emergency-worker-threshold|--switch-cooldown-seconds)
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "${CODEX_QUOTA_BIN}" || ! -x "${CODEX_QUOTA_BIN}" ]]; then
  echo "Error: codex-quota not installed." >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq not installed." >&2
  exit 1
fi

mkdir -p "$CACHE_DIR"

run_with_timeout() {
  local timeout_seconds="$1"
  shift

  /opt/homebrew/bin/python3 - "$timeout_seconds" "$@" <<'PY'
import os
import signal
import subprocess
import sys

timeout_seconds = float(sys.argv[1])
argv = sys.argv[2:]

if not argv:
    sys.exit(64)

proc = subprocess.Popen(argv, start_new_session=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

try:
    stdout, stderr = proc.communicate(timeout=timeout_seconds)
except subprocess.TimeoutExpired:
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        stdout, stderr = proc.communicate(timeout=2)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        stdout, stderr = proc.communicate()
    if stdout:
        sys.stdout.buffer.write(stdout)
    if stderr:
        sys.stderr.buffer.write(stderr)
    sys.exit(124)

if stdout:
    sys.stdout.buffer.write(stdout)
if stderr:
    sys.stderr.buffer.write(stderr)
sys.exit(proc.returncode)
PY
}

load_state_json() {
  if [[ -f "$STATE_FILE" ]] && jq -e 'type == "object"' >/dev/null 2>&1 <"$STATE_FILE"; then
    jq -c '. + {accounts: (.accounts // {})}' "$STATE_FILE"
    return 0
  fi
  printf '{"accounts":{}}\n'
}

write_state_json() {
  local tmp_file="${STATE_FILE}.tmp.$$"
  printf '%s\n' "$STATE_JSON" >"$tmp_file"
  mv "$tmp_file" "$STATE_FILE"
}

state_mark_removed() {
  local label="${1:?label required}"
  local reason="${2:?reason required}"
  local now_epoch="${3:?now epoch required}"
  STATE_JSON="$(
    jq --arg label "$label" --arg reason "$reason" --argjson now "$now_epoch" '
      .accounts[$label] = ((.accounts[$label] // {}) + {
        removed: true,
        next_retry_at: 0,
        last_reset_at: 0,
        last_reason: $reason,
        last_checked_at: $now,
        removed_at: $now
      })
    ' <<<"$STATE_JSON"
  )"
}

state_mark_cooldown() {
  local label="${1:?label required}"
  local retry_at="${2:?retry epoch required}"
  local reason="${3:?reason required}"
  local now_epoch="${4:?now epoch required}"
  STATE_JSON="$(
    jq --arg label "$label" --arg reason "$reason" --argjson retryAt "$retry_at" --argjson now "$now_epoch" '
      .accounts[$label] = ((.accounts[$label] // {}) + {
        removed: false,
        next_retry_at: $retryAt,
        last_reset_at: $retryAt,
        last_reason: $reason,
        last_checked_at: $now
      })
    ' <<<"$STATE_JSON"
  )"
}

state_mark_ready() {
  local label="${1:?label required}"
  local reason="${2:?reason required}"
  local now_epoch="${3:?now epoch required}"
  STATE_JSON="$(
    jq --arg label "$label" --arg reason "$reason" --argjson now "$now_epoch" '
      .accounts[$label] = ((.accounts[$label] // {}) + {
        removed: false,
        next_retry_at: 0,
        last_reset_at: 0,
        last_reason: $reason,
        last_checked_at: $now
      })
    ' <<<"$STATE_JSON"
  )"
}

state_removed() {
  local label="${1:?label required}"
  jq -r --arg label "$label" 'if (.accounts[$label].removed // false) then "1" else "0" end' <<<"$STATE_JSON"
}

state_next_retry_at() {
  local label="${1:?label required}"
  jq -r --arg label "$label" '(.accounts[$label].next_retry_at // 0)' <<<"$STATE_JSON"
}

write_switch_state() {
  local label="${1:?label required}"
  local reason="${2:-switch}"
  local now_epoch
  now_epoch="$(date +%s)"
  cat >"$SWITCH_STATE_FILE" <<EOF
LAST_SWITCH_EPOCH=${now_epoch}
LAST_SWITCH_LABEL=$(printf '%q' "$label")
LAST_SWITCH_REASON=$(printf '%q' "$reason")
EOF
}

load_list_json() {
  local list_json
  list_json="$("${CODEX_QUOTA_BIN}" codex list --json 2>/dev/null || echo '{}')"
  if jq -e 'type == "object"' >/dev/null 2>&1 <<<"$list_json"; then
    printf '%s\n' "$list_json"
  else
    printf '{}\n'
  fi
}

active_label_from_list() {
  jq -r '
    .activeInfo.trackedLabel
    // .activeInfo.activeLabel
    // ([.accounts[]? | select(.isActive == true or .isNativeActive == true)][0].label)
    // empty
  ' <<<"$LIST_JSON"
}

ordered_candidate_labels() {
  local current_label="${1:-}"
  local -a ordered=()
  local -a rotated=()
  local label seen_labels=""

  while IFS= read -r label; do
    [[ -n "$label" ]] || continue
    case " ${seen_labels} " in
      *" ${label} "*) ;;
      *)
        ordered+=("$label")
        seen_labels="${seen_labels} ${label}"
        ;;
    esac
  done < <(jq -r '.accounts[]?.label // empty' <<<"$LIST_JSON")

  if [[ -n "$current_label" ]]; then
    local start_index=-1
    local index=0
    for label in "${ordered[@]}"; do
      if [[ "$label" == "$current_label" ]]; then
        start_index="$index"
        break
      fi
      index=$((index + 1))
    done

    if (( start_index >= 0 )); then
      for (( index=start_index + 1; index<${#ordered[@]}; index++ )); do
        rotated+=("${ordered[index]}")
      done
      for (( index=0; index<start_index; index++ )); do
        rotated+=("${ordered[index]}")
      done
    else
      rotated=("${ordered[@]}")
    fi
  else
    rotated=("${ordered[@]}")
  fi

  if [[ -n "$PREFER_LABEL" ]]; then
    for label in "${rotated[@]}"; do
      if [[ "$label" == "$PREFER_LABEL" ]]; then
        printf '%s\n' "$label"
        break
      fi
    done
  fi

  for label in "${rotated[@]}"; do
    if [[ "$label" != "$current_label" && "$label" != "$PREFER_LABEL" ]]; then
      printf '%s\n' "$label"
    fi
  done
}

is_auth_401_output() {
  local payload="${1:-}"
  grep -Eiq '(HTTP[^0-9]*)?401([^0-9]|$)|unauthorized|invalid credentials|invalid api key|authentication failed with status 401|received 401' <<<"$payload"
}

is_banned_output() {
  local payload="${1:-}"
  grep -Eiq 'account (is )?(banned|suspended|disabled)|access revoked|account revoked|forbidden due to policy|account blocked|policy violation' <<<"$payload"
}

load_account_quota_json() {
  local label="${1:?label required}"
  run_with_timeout "$ACTIVE_QUOTA_TIMEOUT_SECONDS" "${CODEX_QUOTA_BIN}" codex quota "$label" --json
}

quota_account_object() {
  local label="${1:?label required}"
  local quota_json="${2:-[]}"
  jq -c --arg label "$label" '
    ([.[] | select((.label // "") == $label)][0] // .[0] // empty)
  ' <<<"$quota_json"
}

account_is_eligible() {
  local label="${1:?label required}"
  local quota_json="${2:-[]}"
  jq -e --arg label "$label" --argjson primaryThresh "$FIVE_HOUR_THRESHOLD" --argjson weeklyThresh "$WEEKLY_THRESHOLD" '
    ([.[] | select((.label // "") == $label)][0] // .[0] // null) as $account
    | $account != null
    and (($account.usage.rate_limit.allowed // true) == true)
    and (($account.usage.rate_limit.limit_reached // false) | not)
    and (($account.usage.rate_limit.primary_window.used_percent // 100) < $primaryThresh)
    and (($account.usage.rate_limit.secondary_window.used_percent // 100) < $weeklyThresh)
  ' >/dev/null 2>&1 <<<"$quota_json"
}

account_retry_epoch() {
  local label="${1:?label required}"
  local quota_json="${2:-[]}"
  jq -r --arg label "$label" --argjson primaryThresh "$FIVE_HOUR_THRESHOLD" --argjson weeklyThresh "$WEEKLY_THRESHOLD" '
    ([.[] | select((.label // "") == $label)][0] // .[0] // null) as $account
    | if $account == null then
        0
      else
        [
          (
            if (($account.usage.rate_limit.primary_window.used_percent // 0) >= $primaryThresh
                or ($account.usage.rate_limit.limit_reached // false))
            then ($account.usage.rate_limit.primary_window.reset_at // 0)
            else 0
            end
          ),
          (
            if (($account.usage.rate_limit.secondary_window.used_percent // 0) >= $weeklyThresh
                or ($account.usage.rate_limit.limit_reached // false))
            then ($account.usage.rate_limit.secondary_window.reset_at // 0)
            else 0
            end
          )
        ] | max
      end
  ' <<<"$quota_json"
}

switch_account() {
  local label="${1:?label required}"
  "${CODEX_QUOTA_BIN}" codex switch "$label"
}

note_candidate_retry() {
  local label="${1:?label required}"
  local retry_at="${2:?retry epoch required}"
  if (( retry_at <= 0 )); then
    return 0
  fi
  if (( SOONEST_RETRY_AT == 0 || retry_at < SOONEST_RETRY_AT )); then
    SOONEST_RETRY_AT="$retry_at"
    SOONEST_RETRY_LABEL="$label"
  fi
}

now_epoch="$(date +%s)"
STATE_JSON="$(load_state_json)"
LIST_JSON="$(load_list_json)"
ACTIVE_LABEL="$(active_label_from_list)"
if [[ -z "$CURRENT_LABEL" ]]; then
  CURRENT_LABEL="$ACTIVE_LABEL"
fi
SOONEST_RETRY_AT=0
SOONEST_RETRY_LABEL=""

printf 'TRIGGER_REASON=%s\n' "$TRIGGER_REASON"
printf 'ACTIVE_LABEL=%s\n' "$ACTIVE_LABEL"
printf 'CURRENT_LABEL=%s\n' "$CURRENT_LABEL"
printf 'RUNNING_WORKERS=%s\n' "$RUNNING_WORKERS"

case "$TRIGGER_REASON" in
  usage-limit)
    if [[ -n "$CURRENT_LABEL" ]]; then
      current_quota_output="$(load_account_quota_json "$CURRENT_LABEL" 2>&1 || true)"
      if jq -e 'type == "array" and length > 0' >/dev/null 2>&1 <<<"$current_quota_output"; then
        current_retry_at="$(account_retry_epoch "$CURRENT_LABEL" "$current_quota_output")"
        if [[ "$current_retry_at" =~ ^[0-9]+$ ]] && (( current_retry_at > now_epoch )); then
          state_mark_cooldown "$CURRENT_LABEL" "$current_retry_at" "usage-limit" "$now_epoch"
          printf 'MARKED_COOLDOWN_LABEL=%s\n' "$CURRENT_LABEL"
          printf 'MARKED_COOLDOWN_UNTIL=%s\n' "$current_retry_at"
          note_candidate_retry "$CURRENT_LABEL" "$current_retry_at"
        fi
      elif is_auth_401_output "$current_quota_output"; then
        state_mark_removed "$CURRENT_LABEL" "auth-401" "$now_epoch"
        printf 'REMOVED_LABEL=%s\n' "$CURRENT_LABEL"
        printf 'REMOVED_REASON=auth-401\n'
      elif is_banned_output "$current_quota_output"; then
        state_mark_removed "$CURRENT_LABEL" "account-banned" "$now_epoch"
        printf 'REMOVED_LABEL=%s\n' "$CURRENT_LABEL"
        printf 'REMOVED_REASON=account-banned\n'
      fi
    fi
    ;;
  auth-401|account-banned)
    if [[ -n "$CURRENT_LABEL" ]]; then
      state_mark_removed "$CURRENT_LABEL" "$TRIGGER_REASON" "$now_epoch"
      printf 'REMOVED_LABEL=%s\n' "$CURRENT_LABEL"
      printf 'REMOVED_REASON=%s\n' "$TRIGGER_REASON"
    fi
    ;;
  *)
    ;;
esac

CANDIDATE_LABELS=()
while IFS= read -r candidate_label; do
  [[ -n "$candidate_label" ]] || continue
  CANDIDATE_LABELS+=("$candidate_label")
done < <(ordered_candidate_labels "$CURRENT_LABEL")

for label in "${CANDIDATE_LABELS[@]}"; do
  [[ -n "$label" ]] || continue

  if [[ "$(state_removed "$label")" == "1" ]]; then
    continue
  fi

  retry_at="$(state_next_retry_at "$label")"
  if [[ "$retry_at" =~ ^[0-9]+$ ]] && (( retry_at > now_epoch )); then
    note_candidate_retry "$label" "$retry_at"
    continue
  fi

  quota_output="$(load_account_quota_json "$label" 2>&1 || true)"
  if ! jq -e 'type == "array" and length > 0' >/dev/null 2>&1 <<<"$quota_output"; then
    if is_auth_401_output "$quota_output"; then
      state_mark_removed "$label" "auth-401" "$now_epoch"
      printf 'REMOVED_LABEL=%s\n' "$label"
      printf 'REMOVED_REASON=auth-401\n'
    elif is_banned_output "$quota_output"; then
      state_mark_removed "$label" "account-banned" "$now_epoch"
      printf 'REMOVED_LABEL=%s\n' "$label"
      printf 'REMOVED_REASON=account-banned\n'
    else
      short_retry_at=$(( now_epoch + 300 ))
      state_mark_cooldown "$label" "$short_retry_at" "quota-check-failed" "$now_epoch"
      note_candidate_retry "$label" "$short_retry_at"
      printf 'MARKED_COOLDOWN_LABEL=%s\n' "$label"
      printf 'MARKED_COOLDOWN_UNTIL=%s\n' "$short_retry_at"
    fi
    continue
  fi

  if ! account_is_eligible "$label" "$quota_output"; then
    retry_at="$(account_retry_epoch "$label" "$quota_output")"
    if [[ "$retry_at" =~ ^[0-9]+$ ]] && (( retry_at > now_epoch )); then
      state_mark_cooldown "$label" "$retry_at" "quota-window" "$now_epoch"
      note_candidate_retry "$label" "$retry_at"
      printf 'MARKED_COOLDOWN_LABEL=%s\n' "$label"
      printf 'MARKED_COOLDOWN_UNTIL=%s\n' "$retry_at"
    fi
    continue
  fi

  set +e
  switch_output="$(switch_account "$label" 2>&1)"
  switch_status=$?
  set -e
  if (( switch_status == 0 )); then
    state_mark_ready "$label" "switched" "$now_epoch"
    write_state_json
    write_switch_state "$label" "$TRIGGER_REASON"
    printf 'SELECTED_LABEL=%s\n' "$label"
    printf 'SWITCH_DECISION=switched\n'
    printf 'Switching to: %s\n' "$label"
    printf '%s\n' "$switch_output"
    exit 0
  fi

  if is_auth_401_output "$switch_output"; then
    state_mark_removed "$label" "auth-401" "$now_epoch"
    printf 'REMOVED_LABEL=%s\n' "$label"
    printf 'REMOVED_REASON=auth-401\n'
    continue
  fi

  if is_banned_output "$switch_output"; then
    state_mark_removed "$label" "account-banned" "$now_epoch"
    printf 'REMOVED_LABEL=%s\n' "$label"
    printf 'REMOVED_REASON=account-banned\n'
    continue
  fi

  short_retry_at=$(( now_epoch + 300 ))
  state_mark_cooldown "$label" "$short_retry_at" "switch-failed" "$now_epoch"
  note_candidate_retry "$label" "$short_retry_at"
  printf 'MARKED_COOLDOWN_LABEL=%s\n' "$label"
  printf 'MARKED_COOLDOWN_UNTIL=%s\n' "$short_retry_at"
done

write_state_json

if (( SOONEST_RETRY_AT > 0 )); then
  printf 'SWITCH_DECISION=deferred\n'
  printf 'NEXT_RETRY_AT=%s\n' "$SOONEST_RETRY_AT"
  if [[ -n "$SOONEST_RETRY_LABEL" ]]; then
    printf 'NEXT_RETRY_LABEL=%s\n' "$SOONEST_RETRY_LABEL"
  fi
  printf 'No eligible Codex account is ready yet.\n'
  exit 10
fi

printf 'SWITCH_DECISION=failed\n'
printf 'No eligible Codex account remains in the rotation list.\n' >&2
exit 1
