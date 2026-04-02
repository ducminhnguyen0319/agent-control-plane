#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_SCRIPT="${FLOW_ROOT}/tools/vendor/codex-quota-manager/scripts/auto-switch.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

bin_dir="$tmpdir/bin"
cache_dir="$tmpdir/cache"
state_file="$cache_dir/rotation-state.json"
switch_state_file="$cache_dir/last-switch.env"
switch_log="$tmpdir/switch.log"
home_dir="$tmpdir/home"

mkdir -p "$bin_dir" "$cache_dir" "$home_dir"

cat >"$bin_dir/codex-quota" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

scenario="${MOCK_QUOTA_SCENARIO:?}"
fixture_dir="${MOCK_QUOTA_FIXTURE_DIR:?}"
switch_log="${MOCK_QUOTA_SWITCH_LOG:?}"

case "${1:-}:${2:-}:${3:-}" in
  codex:list:--json)
    cat "${fixture_dir}/${scenario}/list.json"
    ;;
  codex:quota:*)
    label="${3:-}"
    if [[ -f "${fixture_dir}/${scenario}/quota-${label}.err" ]]; then
      cat "${fixture_dir}/${scenario}/quota-${label}.err" >&2
      exit 1
    fi
    cat "${fixture_dir}/${scenario}/quota-${label}.json"
    ;;
  codex:switch:*)
    label="${3:-}"
    printf '%s\n' "$label" >>"$switch_log"
    if [[ -f "${fixture_dir}/${scenario}/switch-${label}.err" ]]; then
      cat "${fixture_dir}/${scenario}/switch-${label}.err" >&2
      exit 1
    fi
    printf 'Switched to %s.\n' "$label"
    ;;
  *)
    echo "unexpected codex-quota invocation: $*" >&2
    exit 1
    ;;
esac
EOF

chmod +x "$bin_dir/codex-quota"

fixture_dir="$tmpdir/fixtures"
mkdir -p "$fixture_dir/usage-switch" "$fixture_dir/deferred" "$fixture_dir/auth-401"
mkdir -p "$fixture_dir/stale-cache-healthy"

cat >"$fixture_dir/usage-switch/list.json" <<'EOF'
{"activeInfo":{"trackedLabel":"current-a"},"accounts":[{"label":"current-a","isActive":true},{"label":"next-b"},{"label":"next-c"}]}
EOF
cat >"$fixture_dir/usage-switch/quota-current-a.json" <<'EOF'
[{"label":"current-a","usage":{"rate_limit":{"allowed":false,"limit_reached":true,"primary_window":{"used_percent":92,"reset_at":4102444800},"secondary_window":{"used_percent":65,"reset_at":4102444800}}}}]
EOF
cat >"$fixture_dir/usage-switch/quota-next-b.json" <<'EOF'
[{"label":"next-b","usage":{"rate_limit":{"allowed":false,"limit_reached":true,"primary_window":{"used_percent":81,"reset_at":4102441200},"secondary_window":{"used_percent":20,"reset_at":4102441200}}}}]
EOF
cat >"$fixture_dir/usage-switch/quota-next-c.json" <<'EOF'
[{"label":"next-c","usage":{"rate_limit":{"allowed":true,"limit_reached":false,"primary_window":{"used_percent":12,"reset_at":4102437600},"secondary_window":{"used_percent":18,"reset_at":4102448400}}}}]
EOF

cat >"$fixture_dir/deferred/list.json" <<'EOF'
{"activeInfo":{"trackedLabel":"current-a"},"accounts":[{"label":"current-a","isActive":true},{"label":"next-b"}]}
EOF
cat >"$fixture_dir/deferred/quota-current-a.json" <<'EOF'
[{"label":"current-a","usage":{"rate_limit":{"allowed":false,"limit_reached":true,"primary_window":{"used_percent":91,"reset_at":4102444800},"secondary_window":{"used_percent":30,"reset_at":4102444800}}}}]
EOF
cat >"$fixture_dir/deferred/quota-next-b.json" <<'EOF'
[{"label":"next-b","usage":{"rate_limit":{"allowed":false,"limit_reached":true,"primary_window":{"used_percent":88,"reset_at":4102441200},"secondary_window":{"used_percent":21,"reset_at":4102441200}}}}]
EOF

cat >"$fixture_dir/auth-401/list.json" <<'EOF'
{"activeInfo":{"trackedLabel":"bad-auth"},"accounts":[{"label":"bad-auth","isActive":true},{"label":"good-next"}]}
EOF
cat >"$fixture_dir/auth-401/quota-good-next.json" <<'EOF'
[{"label":"good-next","usage":{"rate_limit":{"allowed":true,"limit_reached":false,"primary_window":{"used_percent":15,"reset_at":4102437600},"secondary_window":{"used_percent":19,"reset_at":4102448400}}}}]
EOF

cat >"$fixture_dir/stale-cache-healthy/list.json" <<'EOF'
{"activeInfo":{"trackedLabel":"current-a"},"accounts":[{"label":"current-a","isActive":true},{"label":"next-b"}]}
EOF
cat >"$fixture_dir/stale-cache-healthy/quota-current-a.json" <<'EOF'
[{"label":"current-a","usage":{"rate_limit":{"allowed":false,"limit_reached":true,"primary_window":{"used_percent":100,"reset_at":4102444800},"secondary_window":{"used_percent":30,"reset_at":4102444800}}}}]
EOF
cat >"$fixture_dir/stale-cache-healthy/quota-next-b.json" <<'EOF'
[{"label":"next-b","usage":{"rate_limit":{"allowed":true,"limit_reached":false,"primary_window":{"used_percent":12,"reset_at":4102437600},"secondary_window":{"used_percent":18,"reset_at":4102448400}}}}]
EOF

run_usage_switch_case() {
  rm -f "$state_file" "$switch_state_file" "$switch_log"

  output="$(
    HOME="$home_dir" \
    PATH="$bin_dir:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    CODEX_QUOTA_BIN="$bin_dir/codex-quota" \
    MOCK_QUOTA_SCENARIO="usage-switch" \
    MOCK_QUOTA_FIXTURE_DIR="$fixture_dir" \
    MOCK_QUOTA_SWITCH_LOG="$switch_log" \
    CODEX_QUOTA_MANAGER_STATE_FILE="$state_file" \
    CODEX_QUOTA_MANAGER_SWITCH_STATE_FILE="$switch_state_file" \
    bash "$SOURCE_SCRIPT" \
      --trigger-reason usage-limit \
      --current-label current-a \
      --five-hour-threshold 70 \
      --weekly-threshold 90
  )"

  grep -q '^SELECTED_LABEL=next-c$' <<<"$output"
  grep -q '^SWITCH_DECISION=switched$' <<<"$output"
  test "$(tail -n 1 "$switch_log")" = "next-c"
  test "$(jq -r '.accounts["current-a"].next_retry_at' "$state_file")" = "4102444800"
  test "$(jq -r '.accounts["next-b"].next_retry_at' "$state_file")" = "4102441200"
  test "$(jq -r '.accounts["next-c"].removed // false' "$state_file")" = "false"
}

run_deferred_case() {
  rm -f "$state_file" "$switch_state_file" "$switch_log"

  set +e
  output="$(
    HOME="$home_dir" \
    PATH="$bin_dir:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    CODEX_QUOTA_BIN="$bin_dir/codex-quota" \
    MOCK_QUOTA_SCENARIO="deferred" \
    MOCK_QUOTA_FIXTURE_DIR="$fixture_dir" \
    MOCK_QUOTA_SWITCH_LOG="$switch_log" \
    CODEX_QUOTA_MANAGER_STATE_FILE="$state_file" \
    CODEX_QUOTA_MANAGER_SWITCH_STATE_FILE="$switch_state_file" \
    bash "$SOURCE_SCRIPT" \
      --trigger-reason usage-limit \
      --current-label current-a \
      --five-hour-threshold 70 \
      --weekly-threshold 90
  )"
  status=$?
  set -e

  test "$status" = "10"
  grep -q '^SWITCH_DECISION=deferred$' <<<"$output"
  grep -q '^NEXT_RETRY_AT=4102441200$' <<<"$output"
  grep -q '^NEXT_RETRY_LABEL=next-b$' <<<"$output"
  test "$(jq -r '.accounts["current-a"].next_retry_at' "$state_file")" = "4102444800"
  test "$(jq -r '.accounts["next-b"].next_retry_at' "$state_file")" = "4102441200"
}

run_auth_401_case() {
  rm -f "$state_file" "$switch_state_file" "$switch_log"

  output="$(
    HOME="$home_dir" \
    PATH="$bin_dir:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    CODEX_QUOTA_BIN="$bin_dir/codex-quota" \
    MOCK_QUOTA_SCENARIO="auth-401" \
    MOCK_QUOTA_FIXTURE_DIR="$fixture_dir" \
    MOCK_QUOTA_SWITCH_LOG="$switch_log" \
    CODEX_QUOTA_MANAGER_STATE_FILE="$state_file" \
    CODEX_QUOTA_MANAGER_SWITCH_STATE_FILE="$switch_state_file" \
    bash "$SOURCE_SCRIPT" \
      --trigger-reason auth-401 \
      --current-label bad-auth \
      --five-hour-threshold 70 \
      --weekly-threshold 90
  )"

  grep -q '^REMOVED_LABEL=bad-auth$' <<<"$output"
  grep -q '^REMOVED_REASON=auth-401$' <<<"$output"
  grep -q '^SELECTED_LABEL=good-next$' <<<"$output"
  grep -q '^SWITCH_DECISION=switched$' <<<"$output"
  test "$(tail -n 1 "$switch_log")" = "good-next"
  test "$(jq -r '.accounts["bad-auth"].removed' "$state_file")" = "true"
}

run_stale_cache_healthy_case() {
  rm -f "$state_file" "$switch_state_file" "$switch_log"
  cat >"$state_file" <<'EOF'
{"accounts":{"next-b":{"removed":false,"next_retry_at":4102441200,"last_reset_at":4102441200,"last_reason":"quota-window","last_checked_at":4102430000}}}
EOF

  output="$(
    HOME="$home_dir" \
    PATH="$bin_dir:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    CODEX_QUOTA_BIN="$bin_dir/codex-quota" \
    MOCK_QUOTA_SCENARIO="stale-cache-healthy" \
    MOCK_QUOTA_FIXTURE_DIR="$fixture_dir" \
    MOCK_QUOTA_SWITCH_LOG="$switch_log" \
    CODEX_QUOTA_MANAGER_STATE_FILE="$state_file" \
    CODEX_QUOTA_MANAGER_SWITCH_STATE_FILE="$switch_state_file" \
    bash "$SOURCE_SCRIPT" \
      --trigger-reason usage-limit \
      --current-label current-a \
      --five-hour-threshold 70 \
      --weekly-threshold 90
  )"

  grep -q '^SELECTED_LABEL=next-b$' <<<"$output"
  grep -q '^SWITCH_DECISION=switched$' <<<"$output"
  test "$(tail -n 1 "$switch_log")" = "next-b"
  test "$(jq -r '.accounts["next-b"].last_reason' "$state_file")" = "switched"
  test "$(jq -r '.accounts["next-b"].next_retry_at' "$state_file")" = "0"
}

run_usage_switch_case
run_deferred_case
run_auth_401_case
run_stale_cache_healthy_case

echo "codex quota manager failure-driven rotation test passed"
