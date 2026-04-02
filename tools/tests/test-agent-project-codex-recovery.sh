#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HELPER_BIN="${FLOW_ROOT}/tools/bin/agent-project-run-codex-resilient"
STATUS_BIN="${FLOW_ROOT}/tools/bin/agent-project-worker-status"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

create_mock_runtime() {
  local case_dir="${1:?case dir required}"
  local state_dir="${case_dir}/state"
  local home_dir="${case_dir}/home"
  local bin_dir="${case_dir}/bin"
  local shared_agent_home="${case_dir}/shared-agent-home"
  local quota_script_dir="${shared_agent_home}/skills/openclaw/codex-quota-manager/scripts"

  mkdir -p "$state_dir" "$home_dir/.codex" "$bin_dir" "$quota_script_dir"

  cat >"${bin_dir}/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

state_dir="${MOCK_CODEX_STATE_DIR:?}"
scenario="${MOCK_CODEX_SCENARIO:-usage-limit}"
invocations_file="${state_dir}/invocations.log"
attempt_file="${state_dir}/attempt"

if [[ "${1:-}" == "login" && "${2:-}" == "status" ]]; then
  if [[ ( "$scenario" == "auth-recovery" || "$scenario" == "auth-recovery-before-thread" ) && ! -f "${state_dir}/auth-ready" ]]; then
    printf 'Authentication required\n' >&2
    exit 1
  fi
  printf 'Logged in using ChatGPT\n'
  exit 0
fi

printf '%s\n' "$*" >>"$invocations_file"

attempt=0
if [[ -f "$attempt_file" ]]; then
  attempt="$(cat "$attempt_file")"
fi

if [[ "${1:-}" == "exec" && "${2:-}" == "resume" ]]; then
  printf '%s\n' '{"type":"thread.started","thread_id":"thread-mock-123"}'
  if [[ "$scenario" == "usage-limit-repeat-after-switch" ]]; then
    printf '%s\n' 'You have reached your Codex usage limits. Please visit https://chatgpt.com/codex/settings/usage'
    echo "$((attempt + 1))" >"$attempt_file"
    exit 1
  fi
  printf '%s\n' '{"type":"turn.started"}'
  printf '%s\n' '{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"resume-ok"}}'
  printf '%s\n' '{"type":"turn.completed","usage":{"input_tokens":1,"output_tokens":1}}'
  echo "$((attempt + 1))" >"$attempt_file"
  exit 0
fi

if [[ "${1:-}" == "exec" ]]; then
  case "$scenario" in
    usage-limit)
      printf '%s\n' '{"type":"thread.started","thread_id":"thread-mock-123"}'
      printf '%s\n' 'You have reached your Codex usage limits. Please visit https://chatgpt.com/codex/settings/usage'
      ;;
    usage-limit-alt-wording)
      printf '%s\n' '{"type":"thread.started","thread_id":"thread-mock-123"}'
      printf '%s\n' 'Rate limit exceeded for the active Codex account. Usage cap reached.'
      ;;
    auth-401)
      printf '%s\n' '{"type":"thread.started","thread_id":"thread-mock-123"}'
      printf '%s\n' 'HTTP 401 Unauthorized: invalid credentials for the active Codex account.'
      ;;
    usage-limit-pre-switched)
      printf '%s\n' '{"type":"thread.started","thread_id":"thread-mock-123"}'
      printf '%s\n' 'You have reached your Codex usage limits. Please visit https://chatgpt.com/codex/settings/usage'
      printf 'manager-staging\n' >"${state_dir}/active-label"
      ;;
    usage-limit-deferred)
      printf '%s\n' '{"type":"thread.started","thread_id":"thread-mock-123"}'
      printf '%s\n' 'You have reached your Codex usage limits. Please visit https://chatgpt.com/codex/settings/usage'
      ;;
    usage-limit-repeat-after-switch)
      printf '%s\n' '{"type":"thread.started","thread_id":"thread-mock-123"}'
      printf '%s\n' 'You have reached your Codex usage limits. Please visit https://chatgpt.com/codex/settings/usage'
      ;;
    auth-recovery)
      printf '%s\n' '{"type":"thread.started","thread_id":"thread-mock-123"}'
      printf '%s\n' 'Authentication required. Please log in.'
      ;;
    auth-recovery-before-thread)
      if [[ "$attempt" == "0" ]]; then
        printf '%s\n' 'Authentication required. Please log in.'
        echo "$((attempt + 1))" >"$attempt_file"
        exit 1
      fi
      printf '%s\n' '{"type":"thread.started","thread_id":"thread-mock-123"}'
      printf '%s\n' '{"type":"turn.started"}'
      printf '%s\n' '{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"initial-retry-ok"}}'
      printf '%s\n' '{"type":"turn.completed","usage":{"input_tokens":1,"output_tokens":1}}'
      echo "$((attempt + 1))" >"$attempt_file"
      exit 0
      ;;
    auth-recovery-alt-wording)
      printf '%s\n' '{"type":"thread.started","thread_id":"thread-mock-123"}'
      printf '%s\n' 'Please authenticate to continue. Login required.'
      ;;
    usage-limit-before-thread)
      if [[ "$attempt" == "0" ]]; then
        printf '%s\n' 'You have reached your Codex usage limits. Please visit https://chatgpt.com/codex/settings/usage'
        echo "$((attempt + 1))" >"$attempt_file"
        exit 1
      fi
      printf '%s\n' '{"type":"thread.started","thread_id":"thread-mock-123"}'
      printf '%s\n' '{"type":"turn.started"}'
      printf '%s\n' '{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"initial-retry-ok"}}'
      printf '%s\n' '{"type":"turn.completed","usage":{"input_tokens":1,"output_tokens":1}}'
      echo "$((attempt + 1))" >"$attempt_file"
      exit 0
      ;;
    *)
      echo "unexpected mock codex scenario: $scenario" >&2
      exit 1
      ;;
  esac
  echo "$((attempt + 1))" >"$attempt_file"
  exit 1
fi

echo "unexpected codex invocation: $*" >&2
exit 1
EOF

  cat >"${bin_dir}/codex-quota" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

state_dir="${MOCK_CODEX_STATE_DIR:?}"
active_label_file="${state_dir}/active-label"
active_label="initial-over-limit"
if [[ -f "$active_label_file" ]]; then
  active_label="$(cat "$active_label_file")"
fi

if [[ "${1:-}" == "codex" && "${2:-}" == "list" && "${3:-}" == "--json" ]]; then
  cat <<JSON
{"activeInfo":{"trackedLabel":"${active_label}"},"accounts":[{"label":"${active_label}","isActive":true,"isNativeActive":false}]}
JSON
  exit 0
fi

exit 0
EOF

  cat >"${quota_script_dir}/auto-switch.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

state_dir="${MOCK_CODEX_STATE_DIR:?}"
scenario="${MOCK_CODEX_SCENARIO:-usage-limit}"
printf '%s\n' "$*" >>"${state_dir}/auto-switch.log"
case "$scenario" in
  usage-limit-pre-switched)
    printf 'SWITCH_DECISION=current-ok\n'
    printf 'SELECTED_LABEL=manager-staging\n'
    printf 'OK: manager-staging (5h used: 8%% < 70%%, weekly used: 63%% < 90%%, workers: 17).\n'
    ;;
  usage-limit-deferred)
    printf 'SWITCH_DECISION=deferred\n'
    printf 'NEXT_RETRY_AT=%s\n' "$(( $(date +%s) + 1800 ))"
    exit 10
    ;;
  *)
    printf '{"account":"rotated","ts":"%s"}\n' "$(date +%s)" >"$HOME/.codex/auth.json"
    printf 'mock-next-account\n' >"${state_dir}/active-label"
    printf 'SWITCH_DECISION=switched\n'
    printf 'SELECTED_LABEL=mock-next-account\n'
    printf 'Switched to mock-next-account.\n'
    ;;
esac
EOF

  chmod +x "${bin_dir}/codex" "${bin_dir}/codex-quota" "${quota_script_dir}/auto-switch.sh"
}

assert_no_failure_reason() {
  local status_out="${1:-}"
  if grep -q '^FAILURE_REASON=' <<<"$status_out"; then
    echo "unexpected FAILURE_REASON in status output:" >&2
    printf '%s\n' "$status_out" >&2
    exit 1
  fi
}

run_usage_limit_recovery_case() {
  local case_dir="${tmpdir}/usage-limit"
  local session="usage-limit-session"
  local runs_root="${case_dir}/runs"
  local run_dir="${runs_root}/${session}"
  local output_file="${run_dir}/${session}.log"
  local prompt_file="${case_dir}/prompt.md"
  local state_dir="${case_dir}/state"
  local home_dir="${case_dir}/home"
  local bin_dir="${case_dir}/bin"
  local shared_agent_home="${case_dir}/shared-agent-home"
  local worktree="${case_dir}/worktree"
  local status_out

  mkdir -p "$run_dir" "$worktree"
  create_mock_runtime "$case_dir"
  printf 'Implement exactly once.\n' >"$prompt_file"
  printf '{"account":"initial"}\n' >"${home_dir}/.codex/auth.json"
  printf 'initial-over-limit\n' >"${state_dir}/active-label"

  PATH="${bin_dir}:$PATH" \
  HOME="$home_dir" \
  ACP_CODEX_QUOTA_BIN="${bin_dir}/codex-quota" \
  ACP_CODEX_QUOTA_MANAGER_SCRIPT="${shared_agent_home}/skills/openclaw/codex-quota-manager/scripts/auto-switch.sh" \
  SHARED_AGENT_HOME="$shared_agent_home" \
  MOCK_CODEX_STATE_DIR="$state_dir" \
  MOCK_CODEX_SCENARIO="usage-limit" \
  bash "$HELPER_BIN" \
    --mode safe \
    --worktree "$worktree" \
    --prompt-file "$prompt_file" \
    --output-file "$output_file" \
    --host-run-dir "$run_dir" \
    --sandbox-run-dir "${case_dir}/sandbox" \
    --safe-profile mock-safe \
    --codex-bin "${bin_dir}/codex" \
    --max-resume-attempts 2 \
    --auth-refresh-timeout-seconds 10 \
    --auth-refresh-poll-seconds 1

  set -a
  # shellcheck source=/dev/null
  source "${run_dir}/runner.env"
  set +a

  test "$RUNNER_STATE" = "succeeded"
  test "$THREAD_ID" = "thread-mock-123"
  test "$RESUME_COUNT" = "1"

  grep -q 'usage limits' "$output_file"
  grep -q 'resume-ok' "$output_file"
  grep -q 'usage-limit detected; attempting failure-driven Codex account switch' "$output_file"
  grep -q 'Switched to mock-next-account.' "$output_file"
  grep -q '^exec --json --profile mock-safe --full-auto$' "${state_dir}/invocations.log"
  grep -q '^exec resume --json --full-auto thread-mock-123 -$' "${state_dir}/invocations.log"

  status_out="$(
    PATH="${bin_dir}:$PATH" \
    HOME="$home_dir" \
    bash "$STATUS_BIN" --runs-root "$runs_root" --session "$session"
  )"
  grep -q '^STATUS=SUCCEEDED$' <<<"$status_out"
  grep -q '^THREAD_ID=thread-mock-123$' <<<"$status_out"
  assert_no_failure_reason "$status_out"
}

run_usage_limit_recovery_with_preswitched_account_case() {
  local case_dir="${tmpdir}/usage-limit-pre-switched"
  local session="usage-limit-pre-switched-session"
  local runs_root="${case_dir}/runs"
  local run_dir="${runs_root}/${session}"
  local output_file="${run_dir}/${session}.log"
  local prompt_file="${case_dir}/prompt.md"
  local state_dir="${case_dir}/state"
  local home_dir="${case_dir}/home"
  local bin_dir="${case_dir}/bin"
  local shared_agent_home="${case_dir}/shared-agent-home"
  local worktree="${case_dir}/worktree"
  local status_out

  mkdir -p "$run_dir" "$worktree"
  create_mock_runtime "$case_dir"
  printf 'Resume after quota rotation.\n' >"$prompt_file"
  printf '{"account":"stable-auth"}\n' >"${home_dir}/.codex/auth.json"
  printf 'initial-over-limit\n' >"${state_dir}/active-label"

  PATH="${bin_dir}:$PATH" \
  HOME="$home_dir" \
  ACP_CODEX_QUOTA_BIN="${bin_dir}/codex-quota" \
  ACP_CODEX_QUOTA_MANAGER_SCRIPT="${shared_agent_home}/skills/openclaw/codex-quota-manager/scripts/auto-switch.sh" \
  SHARED_AGENT_HOME="$shared_agent_home" \
  MOCK_CODEX_STATE_DIR="$state_dir" \
  MOCK_CODEX_SCENARIO="usage-limit-pre-switched" \
  bash "$HELPER_BIN" \
    --mode safe \
    --worktree "$worktree" \
    --prompt-file "$prompt_file" \
    --output-file "$output_file" \
    --host-run-dir "$run_dir" \
    --sandbox-run-dir "${case_dir}/sandbox" \
    --safe-profile mock-safe \
    --codex-bin "${bin_dir}/codex" \
    --max-resume-attempts 2 \
    --auth-refresh-timeout-seconds 10 \
    --auth-refresh-poll-seconds 1

  set -a
  # shellcheck source=/dev/null
  source "${run_dir}/runner.env"
  set +a

  test "$RUNNER_STATE" = "succeeded"
  test "$THREAD_ID" = "thread-mock-123"
  test "$RESUME_COUNT" = "1"

  grep -q 'usage limits' "$output_file"
  grep -q 'OK: manager-staging' "$output_file"
  grep -q 'detected rotated Codex quota account (initial-over-limit -> manager-staging); resuming thread thread-mock-123' "$output_file"
  grep -q 'resume-ok' "$output_file"
  grep -q '^exec --json --profile mock-safe --full-auto$' "${state_dir}/invocations.log"
  grep -q '^exec resume --json --full-auto thread-mock-123 -$' "${state_dir}/invocations.log"

  status_out="$(
    PATH="${bin_dir}:$PATH" \
    HOME="$home_dir" \
    bash "$STATUS_BIN" --runs-root "$runs_root" --session "$session"
  )"
  grep -q '^STATUS=SUCCEEDED$' <<<"$status_out"
  grep -q '^THREAD_ID=thread-mock-123$' <<<"$status_out"
  assert_no_failure_reason "$status_out"
}

run_usage_limit_recovery_alt_wording_case() {
  local case_dir="${tmpdir}/usage-limit-alt-wording"
  local session="usage-limit-alt-wording-session"
  local runs_root="${case_dir}/runs"
  local run_dir="${runs_root}/${session}"
  local output_file="${run_dir}/${session}.log"
  local prompt_file="${case_dir}/prompt.md"
  local state_dir="${case_dir}/state"
  local home_dir="${case_dir}/home"
  local bin_dir="${case_dir}/bin"
  local shared_agent_home="${case_dir}/shared-agent-home"
  local worktree="${case_dir}/worktree"
  local status_out

  mkdir -p "$run_dir" "$worktree"
  create_mock_runtime "$case_dir"
  printf 'Recover after alternate quota wording.\n' >"$prompt_file"
  printf '{"account":"initial"}\n' >"${home_dir}/.codex/auth.json"
  printf 'initial-over-limit\n' >"${state_dir}/active-label"

  PATH="${bin_dir}:$PATH" \
  HOME="$home_dir" \
  ACP_CODEX_QUOTA_BIN="${bin_dir}/codex-quota" \
  ACP_CODEX_QUOTA_MANAGER_SCRIPT="${shared_agent_home}/skills/openclaw/codex-quota-manager/scripts/auto-switch.sh" \
  SHARED_AGENT_HOME="$shared_agent_home" \
  MOCK_CODEX_STATE_DIR="$state_dir" \
  MOCK_CODEX_SCENARIO="usage-limit-alt-wording" \
  bash "$HELPER_BIN" \
    --mode safe \
    --worktree "$worktree" \
    --prompt-file "$prompt_file" \
    --output-file "$output_file" \
    --host-run-dir "$run_dir" \
    --sandbox-run-dir "${case_dir}/sandbox" \
    --safe-profile mock-safe \
    --codex-bin "${bin_dir}/codex" \
    --max-resume-attempts 2 \
    --auth-refresh-timeout-seconds 10 \
    --auth-refresh-poll-seconds 1

  set -a
  # shellcheck source=/dev/null
  source "${run_dir}/runner.env"
  set +a

  test "$RUNNER_STATE" = "succeeded"
  test "$THREAD_ID" = "thread-mock-123"
  test "$RESUME_COUNT" = "1"

  grep -q 'Rate limit exceeded for the active Codex account. Usage cap reached.' "$output_file"
  grep -q 'usage-limit detected; attempting failure-driven Codex account switch' "$output_file"
  grep -q 'resume-ok' "$output_file"

  status_out="$(
    PATH="${bin_dir}:$PATH" \
    HOME="$home_dir" \
    bash "$STATUS_BIN" --runs-root "$runs_root" --session "$session"
  )"
  grep -q '^STATUS=SUCCEEDED$' <<<"$status_out"
  grep -q '^THREAD_ID=thread-mock-123$' <<<"$status_out"
  assert_no_failure_reason "$status_out"
}

run_auth_recovery_without_fingerprint_change_case() {
  local case_dir="${tmpdir}/auth-recovery"
  local session="auth-recovery-session"
  local runs_root="${case_dir}/runs"
  local run_dir="${runs_root}/${session}"
  local output_file="${run_dir}/${session}.log"
  local prompt_file="${case_dir}/prompt.md"
  local state_dir="${case_dir}/state"
  local home_dir="${case_dir}/home"
  local bin_dir="${case_dir}/bin"
  local shared_agent_home="${case_dir}/shared-agent-home"
  local worktree="${case_dir}/worktree"
  local status_out
  local auth_ready_pid

  mkdir -p "$run_dir" "$worktree"
  create_mock_runtime "$case_dir"
  printf 'Recover the interrupted task.\n' >"$prompt_file"
  printf '{"account":"stable"}\n' >"${home_dir}/.codex/auth.json"

  (
    sleep 2
    [[ -d "${state_dir}" ]] && touch "${state_dir}/auth-ready"
  ) &
  auth_ready_pid=$!

  PATH="${bin_dir}:$PATH" \
  HOME="$home_dir" \
  ACP_CODEX_QUOTA_BIN="${bin_dir}/codex-quota" \
  ACP_CODEX_QUOTA_MANAGER_SCRIPT="${shared_agent_home}/skills/openclaw/codex-quota-manager/scripts/auto-switch.sh" \
  SHARED_AGENT_HOME="$shared_agent_home" \
  MOCK_CODEX_STATE_DIR="$state_dir" \
  MOCK_CODEX_SCENARIO="auth-recovery" \
  bash "$HELPER_BIN" \
    --mode safe \
    --worktree "$worktree" \
    --prompt-file "$prompt_file" \
    --output-file "$output_file" \
    --host-run-dir "$run_dir" \
    --sandbox-run-dir "${case_dir}/sandbox" \
    --safe-profile mock-safe \
    --codex-bin "${bin_dir}/codex" \
    --max-resume-attempts 2 \
    --auth-refresh-timeout-seconds 10 \
    --auth-refresh-poll-seconds 1

  set -a
  # shellcheck source=/dev/null
  source "${run_dir}/runner.env"
  set +a

  test "$RUNNER_STATE" = "succeeded"
  test "$THREAD_ID" = "thread-mock-123"
  test "$RESUME_COUNT" = "1"

  grep -q 'Authentication required. Please log in.' "$output_file"
  grep -q 'Codex auth is healthy again; resuming thread thread-mock-123' "$output_file"
  grep -q 'resume-ok' "$output_file"
  grep -q '^exec --json --profile mock-safe --full-auto$' "${state_dir}/invocations.log"
  grep -q '^exec resume --json --full-auto thread-mock-123 -$' "${state_dir}/invocations.log"

  status_out="$(
    PATH="${bin_dir}:$PATH" \
    HOME="$home_dir" \
    bash "$STATUS_BIN" --runs-root "$runs_root" --session "$session"
  )"
  grep -q '^STATUS=SUCCEEDED$' <<<"$status_out"
  grep -q '^THREAD_ID=thread-mock-123$' <<<"$status_out"
  assert_no_failure_reason "$status_out"
  wait "$auth_ready_pid"
}

run_auth_recovery_alt_wording_case() {
  local case_dir="${tmpdir}/auth-recovery-alt-wording"
  local session="auth-recovery-alt-wording-session"
  local runs_root="${case_dir}/runs"
  local run_dir="${runs_root}/${session}"
  local output_file="${run_dir}/${session}.log"
  local prompt_file="${case_dir}/prompt.md"
  local state_dir="${case_dir}/state"
  local home_dir="${case_dir}/home"
  local bin_dir="${case_dir}/bin"
  local shared_agent_home="${case_dir}/shared-agent-home"
  local worktree="${case_dir}/worktree"
  local status_out
  local auth_ready_pid

  mkdir -p "$run_dir" "$worktree"
  create_mock_runtime "$case_dir"
  printf 'Recover the interrupted task with alternate auth wording.\n' >"$prompt_file"
  printf '{"account":"stable"}\n' >"${home_dir}/.codex/auth.json"

  (
    sleep 2
    [[ -d "${state_dir}" ]] && touch "${state_dir}/auth-ready"
  ) &
  auth_ready_pid=$!

  PATH="${bin_dir}:$PATH" \
  HOME="$home_dir" \
  ACP_CODEX_QUOTA_BIN="${bin_dir}/codex-quota" \
  ACP_CODEX_QUOTA_MANAGER_SCRIPT="${shared_agent_home}/skills/openclaw/codex-quota-manager/scripts/auto-switch.sh" \
  SHARED_AGENT_HOME="$shared_agent_home" \
  MOCK_CODEX_STATE_DIR="$state_dir" \
  MOCK_CODEX_SCENARIO="auth-recovery-alt-wording" \
  bash "$HELPER_BIN" \
    --mode safe \
    --worktree "$worktree" \
    --prompt-file "$prompt_file" \
    --output-file "$output_file" \
    --host-run-dir "$run_dir" \
    --sandbox-run-dir "${case_dir}/sandbox" \
    --safe-profile mock-safe \
    --codex-bin "${bin_dir}/codex" \
    --max-resume-attempts 2 \
    --auth-refresh-timeout-seconds 10 \
    --auth-refresh-poll-seconds 1

  set -a
  # shellcheck source=/dev/null
  source "${run_dir}/runner.env"
  set +a

  test "$RUNNER_STATE" = "succeeded"
  test "$THREAD_ID" = "thread-mock-123"
  test "$RESUME_COUNT" = "1"

  grep -q 'Please authenticate to continue. Login required.' "$output_file"
  grep -q 'Codex auth is healthy again; resuming thread thread-mock-123' "$output_file"
  grep -q 'resume-ok' "$output_file"

  status_out="$(
    PATH="${bin_dir}:$PATH" \
    HOME="$home_dir" \
    bash "$STATUS_BIN" --runs-root "$runs_root" --session "$session"
  )"
  grep -q '^STATUS=SUCCEEDED$' <<<"$status_out"
  grep -q '^THREAD_ID=thread-mock-123$' <<<"$status_out"
  assert_no_failure_reason "$status_out"
  wait "$auth_ready_pid"
}

run_auth_recovery_before_thread_case() {
  local case_dir="${tmpdir}/auth-recovery-before-thread"
  local session="auth-recovery-before-thread-session"
  local runs_root="${case_dir}/runs"
  local run_dir="${runs_root}/${session}"
  local output_file="${run_dir}/${session}.log"
  local prompt_file="${case_dir}/prompt.md"
  local state_dir="${case_dir}/state"
  local home_dir="${case_dir}/home"
  local bin_dir="${case_dir}/bin"
  local shared_agent_home="${case_dir}/shared-agent-home"
  local worktree="${case_dir}/worktree"
  local status_out
  local auth_ready_pid

  mkdir -p "$run_dir" "$worktree"
  create_mock_runtime "$case_dir"
  printf 'Recover even when auth fails before the thread starts.\n' >"$prompt_file"
  printf '{"account":"stable"}\n' >"${home_dir}/.codex/auth.json"

  (
    sleep 2
    [[ -d "${state_dir}" ]] && touch "${state_dir}/auth-ready"
  ) &
  auth_ready_pid=$!

  PATH="${bin_dir}:$PATH" \
  HOME="$home_dir" \
  ACP_CODEX_QUOTA_BIN="${bin_dir}/codex-quota" \
  ACP_CODEX_QUOTA_MANAGER_SCRIPT="${shared_agent_home}/skills/openclaw/codex-quota-manager/scripts/auto-switch.sh" \
  SHARED_AGENT_HOME="$shared_agent_home" \
  MOCK_CODEX_STATE_DIR="$state_dir" \
  MOCK_CODEX_SCENARIO="auth-recovery-before-thread" \
  bash "$HELPER_BIN" \
    --mode safe \
    --worktree "$worktree" \
    --prompt-file "$prompt_file" \
    --output-file "$output_file" \
    --host-run-dir "$run_dir" \
    --sandbox-run-dir "${case_dir}/sandbox" \
    --safe-profile mock-safe \
    --codex-bin "${bin_dir}/codex" \
    --max-resume-attempts 2 \
    --auth-refresh-timeout-seconds 10 \
    --auth-refresh-poll-seconds 1

  set -a
  # shellcheck source=/dev/null
  source "${run_dir}/runner.env"
  set +a

  test "$RUNNER_STATE" = "succeeded"
  test "$THREAD_ID" = "thread-mock-123"
  test "$RESUME_COUNT" = "1"

  grep -q 'Authentication required. Please log in.' "$output_file"
  grep -q 'Codex auth is healthy again; resuming initial Codex exec' "$output_file"
  grep -q 'initial-retry-ok' "$output_file"
  test "$(grep -c '^exec --json --profile mock-safe --full-auto$' "${state_dir}/invocations.log" | tr -d '[:space:]')" = "2"
  if grep -q '^exec resume ' "${state_dir}/invocations.log"; then
    echo "unexpected resume invocation for pre-thread auth recovery" >&2
    exit 1
  fi

  status_out="$(
    PATH="${bin_dir}:$PATH" \
    HOME="$home_dir" \
    bash "$STATUS_BIN" --runs-root "$runs_root" --session "$session"
  )"
  grep -q '^STATUS=SUCCEEDED$' <<<"$status_out"
  grep -q '^THREAD_ID=thread-mock-123$' <<<"$status_out"
  assert_no_failure_reason "$status_out"
  wait "$auth_ready_pid"
}

run_usage_limit_recovery_before_thread_case() {
  local case_dir="${tmpdir}/usage-limit-before-thread"
  local session="usage-limit-before-thread-session"
  local runs_root="${case_dir}/runs"
  local run_dir="${runs_root}/${session}"
  local output_file="${run_dir}/${session}.log"
  local prompt_file="${case_dir}/prompt.md"
  local state_dir="${case_dir}/state"
  local home_dir="${case_dir}/home"
  local bin_dir="${case_dir}/bin"
  local shared_agent_home="${case_dir}/shared-agent-home"
  local worktree="${case_dir}/worktree"
  local status_out

  mkdir -p "$run_dir" "$worktree"
  create_mock_runtime "$case_dir"
  printf 'Recover even when quota fails before the thread starts.\n' >"$prompt_file"
  printf '{"account":"initial"}\n' >"${home_dir}/.codex/auth.json"
  printf 'initial-over-limit\n' >"${state_dir}/active-label"

  PATH="${bin_dir}:$PATH" \
  HOME="$home_dir" \
  ACP_CODEX_QUOTA_BIN="${bin_dir}/codex-quota" \
  ACP_CODEX_QUOTA_MANAGER_SCRIPT="${shared_agent_home}/skills/openclaw/codex-quota-manager/scripts/auto-switch.sh" \
  SHARED_AGENT_HOME="$shared_agent_home" \
  MOCK_CODEX_STATE_DIR="$state_dir" \
  MOCK_CODEX_SCENARIO="usage-limit-before-thread" \
  bash "$HELPER_BIN" \
    --mode safe \
    --worktree "$worktree" \
    --prompt-file "$prompt_file" \
    --output-file "$output_file" \
    --host-run-dir "$run_dir" \
    --sandbox-run-dir "${case_dir}/sandbox" \
    --safe-profile mock-safe \
    --codex-bin "${bin_dir}/codex" \
    --max-resume-attempts 2 \
    --auth-refresh-timeout-seconds 10 \
    --auth-refresh-poll-seconds 1

  set -a
  # shellcheck source=/dev/null
  source "${run_dir}/runner.env"
  set +a

  test "$RUNNER_STATE" = "succeeded"
  test "$THREAD_ID" = "thread-mock-123"
  test "$RESUME_COUNT" = "1"

  grep -q 'usage-limit detected; attempting failure-driven Codex account switch' "$output_file"
  grep -q 'detected refreshed Codex auth after quota interruption; resuming initial Codex exec' "$output_file"
  grep -q 'initial-retry-ok' "$output_file"
  test "$(grep -c '^exec --json --profile mock-safe --full-auto$' "${state_dir}/invocations.log" | tr -d '[:space:]')" = "2"
  if grep -q '^exec resume ' "${state_dir}/invocations.log"; then
    echo "unexpected resume invocation for pre-thread quota recovery" >&2
    exit 1
  fi

  status_out="$(
    PATH="${bin_dir}:$PATH" \
    HOME="$home_dir" \
    bash "$STATUS_BIN" --runs-root "$runs_root" --session "$session"
  )"
  grep -q '^STATUS=SUCCEEDED$' <<<"$status_out"
  grep -q '^THREAD_ID=thread-mock-123$' <<<"$status_out"
  assert_no_failure_reason "$status_out"
}

run_auth_401_rotation_case() {
  local case_dir="${tmpdir}/auth-401"
  local session="auth-401-session"
  local runs_root="${case_dir}/runs"
  local run_dir="${runs_root}/${session}"
  local output_file="${run_dir}/${session}.log"
  local prompt_file="${case_dir}/prompt.md"
  local state_dir="${case_dir}/state"
  local home_dir="${case_dir}/home"
  local bin_dir="${case_dir}/bin"
  local shared_agent_home="${case_dir}/shared-agent-home"
  local worktree="${case_dir}/worktree"
  local status_out

  mkdir -p "$run_dir" "$worktree"
  create_mock_runtime "$case_dir"
  printf 'Recover after unauthorized account rotation.\n' >"$prompt_file"
  printf '{"account":"initial"}\n' >"${home_dir}/.codex/auth.json"
  printf 'initial-over-limit\n' >"${state_dir}/active-label"

  PATH="${bin_dir}:$PATH" \
  HOME="$home_dir" \
  ACP_CODEX_QUOTA_BIN="${bin_dir}/codex-quota" \
  ACP_CODEX_QUOTA_MANAGER_SCRIPT="${shared_agent_home}/skills/openclaw/codex-quota-manager/scripts/auto-switch.sh" \
  SHARED_AGENT_HOME="$shared_agent_home" \
  MOCK_CODEX_STATE_DIR="$state_dir" \
  MOCK_CODEX_SCENARIO="auth-401" \
  bash "$HELPER_BIN" \
    --mode safe \
    --worktree "$worktree" \
    --prompt-file "$prompt_file" \
    --output-file "$output_file" \
    --host-run-dir "$run_dir" \
    --sandbox-run-dir "${case_dir}/sandbox" \
    --safe-profile mock-safe \
    --codex-bin "${bin_dir}/codex" \
    --max-resume-attempts 2 \
    --auth-refresh-timeout-seconds 10 \
    --auth-refresh-poll-seconds 1

  set -a
  # shellcheck source=/dev/null
  source "${run_dir}/runner.env"
  set +a

  test "$RUNNER_STATE" = "succeeded"
  test "$THREAD_ID" = "thread-mock-123"
  test "$RESUME_COUNT" = "1"

  grep -q 'HTTP 401 Unauthorized: invalid credentials for the active Codex account.' "$output_file"
  grep -q 'auth-401 detected; attempting failure-driven Codex account switch' "$output_file"
  grep -q 'Switched to mock-next-account.' "$output_file"
  grep -q 'resume-ok' "$output_file"

  status_out="$(
    PATH="${bin_dir}:$PATH" \
    HOME="$home_dir" \
    bash "$STATUS_BIN" --runs-root "$runs_root" --session "$session"
  )"
  grep -q '^STATUS=SUCCEEDED$' <<<"$status_out"
  grep -q '^THREAD_ID=thread-mock-123$' <<<"$status_out"
  assert_no_failure_reason "$status_out"
}

run_usage_limit_deferred_fails_without_timed_retry_case() {
  local case_dir="${tmpdir}/usage-limit-deferred"
  local session="usage-limit-deferred-session"
  local runs_root="${case_dir}/runs"
  local run_dir="${runs_root}/${session}"
  local output_file="${run_dir}/${session}.log"
  local prompt_file="${case_dir}/prompt.md"
  local state_dir="${case_dir}/state"
  local home_dir="${case_dir}/home"
  local bin_dir="${case_dir}/bin"
  local shared_agent_home="${case_dir}/shared-agent-home"
  local worktree="${case_dir}/worktree"
  local status_out
  local started_at ended_at elapsed

  mkdir -p "$run_dir" "$worktree"
  create_mock_runtime "$case_dir"
  printf 'Do not keep rotating accounts in the background.\n' >"$prompt_file"
  printf '{"account":"initial"}\n' >"${home_dir}/.codex/auth.json"
  printf 'initial-over-limit\n' >"${state_dir}/active-label"

  started_at="$(date +%s)"
  set +e
  PATH="${bin_dir}:$PATH" \
  HOME="$home_dir" \
  ACP_CODEX_QUOTA_BIN="${bin_dir}/codex-quota" \
  ACP_CODEX_QUOTA_MANAGER_SCRIPT="${shared_agent_home}/skills/openclaw/codex-quota-manager/scripts/auto-switch.sh" \
  SHARED_AGENT_HOME="$shared_agent_home" \
  MOCK_CODEX_STATE_DIR="$state_dir" \
  MOCK_CODEX_SCENARIO="usage-limit-deferred" \
  bash "$HELPER_BIN" \
    --mode safe \
    --worktree "$worktree" \
    --prompt-file "$prompt_file" \
    --output-file "$output_file" \
    --host-run-dir "$run_dir" \
    --sandbox-run-dir "${case_dir}/sandbox" \
    --safe-profile mock-safe \
    --codex-bin "${bin_dir}/codex" \
    --max-resume-attempts 2 \
    --auth-refresh-timeout-seconds 30 \
    --auth-refresh-poll-seconds 1
  status=$?
  set -e
  ended_at="$(date +%s)"
  elapsed=$((ended_at - started_at))

  test "$status" != "0"
  test "$elapsed" -lt 5

  set -a
  # shellcheck source=/dev/null
  source "${run_dir}/runner.env"
  set +a

  test "$RUNNER_STATE" = "failed"
  test "$LAST_FAILURE_REASON" = "quota-switch-deferred"
  grep -q 'automatic timed re-tries are disabled for safety' "$output_file"
  test "$(wc -l <"${state_dir}/auto-switch.log" | tr -d '[:space:]')" = "1"

  status_out="$(
    PATH="${bin_dir}:$PATH" \
    HOME="$home_dir" \
    bash "$STATUS_BIN" --runs-root "$runs_root" --session "$session"
  )"
  grep -q '^STATUS=FAILED$' <<<"$status_out"
  grep -q '^FAILURE_REASON=quota-switch-deferred$' <<<"$status_out"
}

run_usage_limit_repeat_after_switch_fails_after_one_rotation_case() {
  local case_dir="${tmpdir}/usage-limit-repeat-after-switch"
  local session="usage-limit-repeat-after-switch-session"
  local runs_root="${case_dir}/runs"
  local run_dir="${runs_root}/${session}"
  local output_file="${run_dir}/${session}.log"
  local prompt_file="${case_dir}/prompt.md"
  local state_dir="${case_dir}/state"
  local home_dir="${case_dir}/home"
  local bin_dir="${case_dir}/bin"
  local shared_agent_home="${case_dir}/shared-agent-home"
  local worktree="${case_dir}/worktree"
  local status_out

  mkdir -p "$run_dir" "$worktree"
  create_mock_runtime "$case_dir"
  printf 'If quota still fails after one switch, stop and surface it.\n' >"$prompt_file"
  printf '{"account":"initial"}\n' >"${home_dir}/.codex/auth.json"
  printf 'initial-over-limit\n' >"${state_dir}/active-label"

  set +e
  PATH="${bin_dir}:$PATH" \
  HOME="$home_dir" \
  ACP_CODEX_QUOTA_BIN="${bin_dir}/codex-quota" \
  ACP_CODEX_QUOTA_MANAGER_SCRIPT="${shared_agent_home}/skills/openclaw/codex-quota-manager/scripts/auto-switch.sh" \
  SHARED_AGENT_HOME="$shared_agent_home" \
  MOCK_CODEX_STATE_DIR="$state_dir" \
  MOCK_CODEX_SCENARIO="usage-limit-repeat-after-switch" \
  bash "$HELPER_BIN" \
    --mode safe \
    --worktree "$worktree" \
    --prompt-file "$prompt_file" \
    --output-file "$output_file" \
    --host-run-dir "$run_dir" \
    --sandbox-run-dir "${case_dir}/sandbox" \
    --safe-profile mock-safe \
    --codex-bin "${bin_dir}/codex" \
    --max-resume-attempts 3 \
    --auth-refresh-timeout-seconds 10 \
    --auth-refresh-poll-seconds 1
  status=$?
  set -e

  test "$status" != "0"

  set -a
  # shellcheck source=/dev/null
  source "${run_dir}/runner.env"
  set +a

  test "$RUNNER_STATE" = "failed"
  test "$RESUME_COUNT" = "1"
  test "$LAST_FAILURE_REASON" = "quota-switch-attempt-limit"
  grep -q 'automatic Codex quota switching already ran 1 time(s) in this worker; refusing another rotation' "$output_file"
  test "$(wc -l <"${state_dir}/auto-switch.log" | tr -d '[:space:]')" = "1"

  status_out="$(
    PATH="${bin_dir}:$PATH" \
    HOME="$home_dir" \
    bash "$STATUS_BIN" --runs-root "$runs_root" --session "$session"
  )"
  grep -q '^STATUS=FAILED$' <<<"$status_out"
  grep -q '^FAILURE_REASON=quota-switch-attempt-limit$' <<<"$status_out"
}

run_result_env_completion_override_case() {
  local case_dir="${tmpdir}/result-only"
  local runs_root="${case_dir}/runs"
  local session="result-only-session"
  local run_dir="${runs_root}/${session}"
  local output_file="${run_dir}/${session}.log"
  local result_file="${run_dir}/result.env"
  local status_out

  mkdir -p "$run_dir"
  cat >"$output_file" <<'EOF'
You have reached your Codex usage limits. Please visit https://chatgpt.com/codex/settings/usage
EOF
  cat >"$result_file" <<'EOF'
OUTCOME=reported
ACTION=host-comment-scheduled-report
EOF

  status_out="$(bash "$STATUS_BIN" --runs-root "$runs_root" --session "$session")"
  grep -q '^STATUS=SUCCEEDED$' <<<"$status_out"
  grep -q '^RESULT_ONLY_COMPLETION=yes$' <<<"$status_out"
  assert_no_failure_reason "$status_out"
}

run_usage_limit_recovery_case
run_usage_limit_recovery_with_preswitched_account_case
run_usage_limit_recovery_alt_wording_case
run_auth_recovery_without_fingerprint_change_case
run_auth_recovery_alt_wording_case
run_auth_recovery_before_thread_case
run_auth_401_rotation_case
run_usage_limit_recovery_before_thread_case
run_usage_limit_deferred_fails_without_timed_retry_case
run_usage_limit_repeat_after_switch_fails_after_one_rotation_case
run_result_env_completion_override_case

echo "agent-project codex recovery test passed"
