#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUTPUT_DIR="${ROOT_DIR}/assets/readme"
PNG_OUT="${OUTPUT_DIR}/dashboard-demo.png"
GIF_OUT="${OUTPUT_DIR}/dashboard-demo.gif"

require_bin() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "missing required dependency: $name" >&2
    exit 1
  fi
}

require_bin python3
require_bin ffmpeg
require_bin playwright
require_bin curl

PLAYWRIGHT_CLI="$(command -v playwright)"
PLAYWRIGHT_PACKAGE_ROOT="$(
  python3 - "$PLAYWRIGHT_CLI" <<'PY'
import os
import sys

print(os.path.dirname(os.path.realpath(sys.argv[1])))
PY
)"

tmpdir="/tmp/acp-dashboard-demo"
rm -rf "${tmpdir}"
server_pid=""
controller_pid=""
port="$(
  python3 - <<'PY'
import socket

sock = socket.socket()
sock.bind(("127.0.0.1", 0))
print(sock.getsockname()[1])
sock.close()
PY
)"

cleanup() {
  if [[ -n "${server_pid}" ]]; then
    kill "${server_pid}" >/dev/null 2>&1 || true
    wait "${server_pid}" 2>/dev/null || true
  fi
  if [[ -n "${controller_pid}" ]]; then
    kill "${controller_pid}" >/dev/null 2>&1 || true
    wait "${controller_pid}" 2>/dev/null || true
  fi
  rm -rf "${tmpdir}"
}
trap cleanup EXIT

profile_registry_root="${tmpdir}/profiles"

# --- demo-retail profile (openclaw, heavier fixture) ---
retail_dir="${profile_registry_root}/demo-retail"
retail_runs="${tmpdir}/runtime/demo-retail/runs"
retail_history="${tmpdir}/runtime/demo-retail/history"
retail_state="${tmpdir}/runtime/demo-retail/state"

# --- demo-platform profile (claude, lighter fixture) ---
platform_dir="${profile_registry_root}/demo-platform"
platform_runs="${tmpdir}/runtime/demo-platform/runs"
platform_history="${tmpdir}/runtime/demo-platform/history"
platform_state="${tmpdir}/runtime/demo-platform/state"

frames_dir="${tmpdir}/frames"

mkdir -p \
  "${retail_dir}" \
  "${retail_runs}/demo-issue-31" \
  "${retail_runs}/demo-issue-28" \
  "${retail_runs}/demo-issue-25" \
  "${retail_history}/demo-issue-24" \
  "${retail_history}/demo-issue-22" \
  "${retail_history}/demo-issue-19" \
  "${retail_history}/demo-issue-17" \
  "${retail_history}/demo-pr-6" \
  "${retail_history}/demo-issue-15" \
  "${retail_state}/resident-workers/issues/31" \
  "${retail_state}/resident-workers/issues/28" \
  "${retail_state}/resident-workers/issues/25" \
  "${retail_state}/resident-workers/issues/issue-lane-recurring-general-openclaw-safe" \
  "${retail_state}/retries/providers" \
  "${retail_state}/scheduled-issues" \
  "${retail_state}/resident-workers/issue-queue/pending" \
  "${platform_dir}" \
  "${platform_runs}/demo-platform-issue-8" \
  "${platform_history}/demo-platform-issue-7" \
  "${platform_history}/demo-platform-issue-6" \
  "${platform_state}/resident-workers/issues/8" \
  "${platform_state}/resident-workers/issues/issue-lane-recurring-general-claude-safe" \
  "${platform_state}/retries/providers" \
  "${platform_state}/scheduled-issues" \
  "${platform_state}/resident-workers/issue-queue/pending" \
  "${frames_dir}" \
  "${OUTPUT_DIR}"

# Keep a live PID so controllers show as "live" in the dashboard
sleep 600 &
controller_pid="$!"

# =========================================================
# demo-retail profile
# =========================================================

cat >"${retail_dir}/control-plane.yaml" <<EOF
schema_version: "1"
id: "demo-retail"
repo:
  slug: "example/retail-agent-demo"
  root: "${tmpdir}/repos/retail"
  default_branch: "main"
runtime:
  orchestrator_agent_root: "${tmpdir}/runtime/demo-retail"
  worktree_root: "${tmpdir}/worktrees/retail"
  agent_repo_root: "${tmpdir}/repos/retail"
  runs_root: "${retail_runs}"
  state_root: "${retail_state}"
  history_root: "${retail_history}"
  retained_repo_root: "${tmpdir}/repos/retail"
  vscode_workspace_file: "${tmpdir}/demo-retail.code-workspace"
session_naming:
  issue_prefix: "demo-issue-"
  pr_prefix: "demo-pr-"
execution:
  coding_worker: "openclaw"
  openclaw:
    model: "openrouter/qwen/qwen3.6-plus:free"
    thinking: "low"
    timeout_seconds: 600
EOF

# --- Active runs ---

cat >"${retail_runs}/demo-issue-31/run.env" <<EOF
TASK_KIND=issue
TASK_ID=31
SESSION=demo-issue-31
MODE=safe
STARTED_AT=2026-04-03T09:10:00Z
CODING_WORKER=openclaw
RESIDENT_WORKER_KEY=issue-lane-recurring-general-openclaw-safe
BRANCH=agent/demo-retail/issue-31
OPENCLAW_MODEL=openrouter/qwen/qwen3.6-plus:free
EOF

cat >"${retail_runs}/demo-issue-31/runner.env" <<'EOF'
RUNNER_STATE=running
ATTEMPT=1
UPDATED_AT=2026-04-03T09:10:05Z
EOF

cat >"${retail_runs}/demo-issue-28/run.env" <<'EOF'
TASK_KIND=issue
TASK_ID=28
SESSION=demo-issue-28
MODE=safe
STARTED_AT=2026-04-03T08:40:00Z
CODING_WORKER=openclaw
BRANCH=agent/demo-retail/issue-28
OPENCLAW_MODEL=openrouter/qwen/qwen3.6-plus:free
EOF

cat >"${retail_runs}/demo-issue-28/runner.env" <<'EOF'
RUNNER_STATE=succeeded
LAST_EXIT_CODE=0
UPDATED_AT=2026-04-03T08:55:00Z
EOF

cat >"${retail_runs}/demo-issue-28/result.env" <<'EOF'
OUTCOME=implemented
ACTION=host-publish-issue-pr
UPDATED_AT=2026-04-03T08:55:30Z
EOF

cat >"${retail_runs}/demo-issue-25/run.env" <<'EOF'
TASK_KIND=issue
TASK_ID=25
SESSION=demo-issue-25
MODE=safe
STARTED_AT=2026-04-03T07:55:00Z
CODING_WORKER=openclaw
BRANCH=agent/demo-retail/issue-25
OPENCLAW_MODEL=openrouter/qwen/qwen3.6-plus:free
EOF

cat >"${retail_runs}/demo-issue-25/runner.env" <<'EOF'
RUNNER_STATE=succeeded
LAST_EXIT_CODE=0
LAST_FAILURE_REASON=provider-quota-limit
UPDATED_AT=2026-04-03T08:05:00Z
EOF

cat >"${retail_runs}/demo-issue-25/result.env" <<'EOF'
OUTCOME=blocked
ACTION=host-comment-blocked
FAILURE_REASON=provider-quota-limit
UPDATED_AT=2026-04-03T08:05:30Z
EOF

# --- History runs (Recent Completed) ---

cat >"${retail_history}/demo-issue-24/run.env" <<'EOF'
TASK_KIND=issue
TASK_ID=24
SESSION=demo-issue-24
MODE=safe
STARTED_AT=2026-04-03T07:20:00Z
CODING_WORKER=openclaw
EOF

cat >"${retail_history}/demo-issue-24/runner.env" <<'EOF'
RUNNER_STATE=succeeded
LAST_EXIT_CODE=0
UPDATED_AT=2026-04-03T07:36:00Z
EOF

cat >"${retail_history}/demo-issue-24/result.env" <<'EOF'
OUTCOME=implemented
ACTION=host-publish-issue-pr
UPDATED_AT=2026-04-03T07:36:30Z
EOF

cat >"${retail_history}/demo-issue-22/run.env" <<'EOF'
TASK_KIND=issue
TASK_ID=22
SESSION=demo-issue-22
MODE=safe
STARTED_AT=2026-04-03T06:10:00Z
CODING_WORKER=openclaw
EOF

cat >"${retail_history}/demo-issue-22/runner.env" <<'EOF'
RUNNER_STATE=succeeded
LAST_EXIT_CODE=0
UPDATED_AT=2026-04-03T06:22:00Z
EOF

cat >"${retail_history}/demo-issue-22/result.env" <<'EOF'
OUTCOME=reported
ACTION=host-comment-scheduled-report
UPDATED_AT=2026-04-03T06:22:30Z
EOF

cat >"${retail_history}/demo-issue-19/run.env" <<'EOF'
TASK_KIND=issue
TASK_ID=19
SESSION=demo-issue-19
MODE=safe
STARTED_AT=2026-04-02T21:05:00Z
CODING_WORKER=openclaw
EOF

cat >"${retail_history}/demo-issue-19/runner.env" <<'EOF'
RUNNER_STATE=succeeded
LAST_EXIT_CODE=0
UPDATED_AT=2026-04-02T21:19:00Z
EOF

cat >"${retail_history}/demo-issue-19/result.env" <<'EOF'
OUTCOME=implemented
ACTION=host-publish-issue-pr
UPDATED_AT=2026-04-02T21:19:30Z
EOF

cat >"${retail_history}/demo-issue-17/run.env" <<'EOF'
TASK_KIND=issue
TASK_ID=17
SESSION=demo-issue-17
MODE=safe
STARTED_AT=2026-04-02T18:30:00Z
CODING_WORKER=openclaw
EOF

cat >"${retail_history}/demo-issue-17/runner.env" <<'EOF'
RUNNER_STATE=succeeded
LAST_EXIT_CODE=0
UPDATED_AT=2026-04-02T18:45:00Z
EOF

cat >"${retail_history}/demo-issue-17/result.env" <<'EOF'
OUTCOME=implemented
ACTION=host-publish-issue-pr
UPDATED_AT=2026-04-02T18:45:30Z
EOF

cat >"${retail_history}/demo-pr-6/run.env" <<'EOF'
TASK_KIND=pr
TASK_ID=6
SESSION=demo-pr-6
MODE=safe
STARTED_AT=2026-04-02T17:10:00Z
CODING_WORKER=openclaw
EOF

cat >"${retail_history}/demo-pr-6/runner.env" <<'EOF'
RUNNER_STATE=succeeded
LAST_EXIT_CODE=0
UPDATED_AT=2026-04-02T17:22:00Z
EOF

cat >"${retail_history}/demo-pr-6/result.env" <<'EOF'
OUTCOME=implemented
ACTION=host-approve-merge-pr
UPDATED_AT=2026-04-02T17:22:30Z
EOF

cat >"${retail_history}/demo-issue-15/run.env" <<'EOF'
TASK_KIND=issue
TASK_ID=15
SESSION=demo-issue-15
MODE=safe
STARTED_AT=2026-04-02T14:00:00Z
CODING_WORKER=openclaw
EOF

cat >"${retail_history}/demo-issue-15/runner.env" <<'EOF'
RUNNER_STATE=succeeded
LAST_FAILURE_REASON=issue-worker-blocked
LAST_EXIT_CODE=1
UPDATED_AT=2026-04-02T14:12:00Z
EOF

cat >"${retail_history}/demo-issue-15/result.env" <<'EOF'
OUTCOME=blocked
ACTION=host-comment-blocked
FAILURE_REASON=issue-worker-blocked
UPDATED_AT=2026-04-02T14:12:30Z
EOF

# --- Resident controllers ---

cat >"${retail_state}/resident-workers/issues/31/controller.env" <<EOF
ISSUE_ID=31
SESSION=demo-issue-31
CONTROLLER_PID=${controller_pid}
CONTROLLER_MODE=safe
CONTROLLER_LOOP_COUNT=1
CONTROLLER_STATE=running
CONTROLLER_REASON=''
ACTIVE_RESIDENT_WORKER_KEY=issue-lane-recurring-general-openclaw-safe
ACTIVE_RESIDENT_LANE_KIND=recurring
ACTIVE_RESIDENT_LANE_VALUE=general
ACTIVE_PROVIDER_BACKEND=openclaw
ACTIVE_PROVIDER_MODEL=openrouter/qwen/qwen3.6-plus:free
PROVIDER_SWITCH_COUNT=0
PROVIDER_FAILOVER_COUNT=0
PROVIDER_WAIT_COUNT=0
PROVIDER_WAIT_TOTAL_SECONDS=0
PROVIDER_LAST_WAIT_SECONDS=0
UPDATED_AT=2026-04-03T09:10:05Z
EOF

cat >"${retail_state}/resident-workers/issues/28/controller.env" <<'EOF'
ISSUE_ID=28
SESSION=demo-issue-28
CONTROLLER_PID=99999
CONTROLLER_MODE=safe
CONTROLLER_LOOP_COUNT=2
CONTROLLER_STATE=stopped
CONTROLLER_REASON=session-succeeded
ACTIVE_RESIDENT_WORKER_KEY=issue-lane-recurring-general-openclaw-safe
ACTIVE_RESIDENT_LANE_KIND=recurring
ACTIVE_RESIDENT_LANE_VALUE=general
ACTIVE_PROVIDER_BACKEND=openclaw
ACTIVE_PROVIDER_MODEL=openrouter/qwen/qwen3.6-plus:free
PROVIDER_SWITCH_COUNT=0
PROVIDER_FAILOVER_COUNT=0
PROVIDER_WAIT_COUNT=0
UPDATED_AT=2026-04-03T08:55:30Z
EOF

cat >"${retail_state}/resident-workers/issues/25/controller.env" <<'EOF'
ISSUE_ID=25
SESSION=demo-issue-25
CONTROLLER_PID=99998
CONTROLLER_MODE=safe
CONTROLLER_LOOP_COUNT=3
CONTROLLER_STATE=stopped
CONTROLLER_REASON=session-blocked
ACTIVE_RESIDENT_WORKER_KEY=issue-lane-recurring-general-openclaw-safe
ACTIVE_RESIDENT_LANE_KIND=recurring
ACTIVE_RESIDENT_LANE_VALUE=general
ACTIVE_PROVIDER_BACKEND=openclaw
ACTIVE_PROVIDER_MODEL=openrouter/qwen/qwen3.6-plus:free
PROVIDER_SWITCH_COUNT=1
PROVIDER_FAILOVER_COUNT=1
PROVIDER_WAIT_COUNT=3
PROVIDER_WAIT_TOTAL_SECONDS=75
PROVIDER_LAST_WAIT_SECONDS=30
UPDATED_AT=2026-04-03T08:05:30Z
EOF

# --- Resident worker lane metadata ---

cat >"${retail_state}/resident-workers/issues/issue-lane-recurring-general-openclaw-safe/metadata.env" <<'EOF'
RESIDENT_WORKER_KIND=issue
RESIDENT_WORKER_SCOPE=lane
RESIDENT_WORKER_KEY=issue-lane-recurring-general-openclaw-safe
ISSUE_ID=31
CODING_WORKER=openclaw
TASK_COUNT=14
LAST_STATUS=running
LAST_STARTED_AT=2026-04-03T09:10:00Z
LAST_FINISHED_AT=''
LAST_RUN_SESSION=demo-issue-31
LAST_OUTCOME=implemented
LAST_ACTION=host-publish-issue-pr
EOF

# --- Provider cooldown ---

cooldown_epoch="$(python3 -c "import time; print(int(time.time()) + 1800)")"
cooldown_at="$(python3 -c "from datetime import datetime,timezone; import time; print(datetime.fromtimestamp(int(time.time())+1800,tz=timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))")"
cat >"${retail_state}/retries/providers/openclaw-openrouter-qwen-qwen3.6-plus-free.env" <<EOF
ATTEMPTS=3
NEXT_ATTEMPT_EPOCH=${cooldown_epoch}
NEXT_ATTEMPT_AT=${cooldown_at}
LAST_REASON=provider-quota-limit
UPDATED_AT=2026-04-03T08:05:30Z
EOF

# --- Scheduled issues ---

cat >"${retail_state}/scheduled-issues/22.env" <<'EOF'
INTERVAL_SECONDS=3600
LAST_STARTED_AT=2026-04-03T06:10:00Z
NEXT_DUE_AT=2026-04-03T07:10:00Z
UPDATED_AT=2026-04-03T06:10:00Z
EOF

cat >"${retail_state}/scheduled-issues/17.env" <<'EOF'
INTERVAL_SECONDS=1800
LAST_STARTED_AT=2026-04-03T09:00:00Z
NEXT_DUE_AT=2026-04-03T09:30:00Z
UPDATED_AT=2026-04-03T09:00:00Z
EOF

cat >"${retail_state}/scheduled-issues/9.env" <<'EOF'
INTERVAL_SECONDS=7200
LAST_STARTED_AT=2026-04-03T07:00:00Z
NEXT_DUE_AT=2026-04-03T09:00:00Z
UPDATED_AT=2026-04-03T07:00:00Z
EOF

# --- Pending queue ---

cat >"${retail_state}/resident-workers/issue-queue/pending/issue-33.env" <<'EOF'
ISSUE_ID=33
SESSION=demo-issue-33
UPDATED_AT=2026-04-03T09:05:00Z
EOF

cat >"${retail_state}/resident-workers/issue-queue/pending/issue-34.env" <<'EOF'
ISSUE_ID=34
SESSION=demo-issue-34
UPDATED_AT=2026-04-03T09:06:00Z
EOF

cat >"${retail_state}/resident-workers/issue-queue/pending/issue-35.env" <<'EOF'
ISSUE_ID=35
SESSION=demo-issue-35
UPDATED_AT=2026-04-03T09:07:00Z
EOF

# =========================================================
# demo-platform profile
# =========================================================

cat >"${platform_dir}/control-plane.yaml" <<EOF
schema_version: "1"
id: "demo-platform"
repo:
  slug: "example/platform-services"
  root: "${tmpdir}/repos/platform"
  default_branch: "main"
runtime:
  orchestrator_agent_root: "${tmpdir}/runtime/demo-platform"
  worktree_root: "${tmpdir}/worktrees/platform"
  agent_repo_root: "${tmpdir}/repos/platform"
  runs_root: "${platform_runs}"
  state_root: "${platform_state}"
  history_root: "${platform_history}"
  retained_repo_root: "${tmpdir}/repos/platform"
  vscode_workspace_file: "${tmpdir}/demo-platform.code-workspace"
session_naming:
  issue_prefix: "demo-platform-issue-"
  pr_prefix: "demo-platform-pr-"
execution:
  coding_worker: "claude"
  claude:
    model: "sonnet"
    permission_mode: "acceptEdits"
    timeout_seconds: 900
EOF

# Active run

cat >"${platform_runs}/demo-platform-issue-8/run.env" <<'EOF'
TASK_KIND=issue
TASK_ID=8
SESSION=demo-platform-issue-8
MODE=safe
STARTED_AT=2026-04-03T08:50:00Z
CODING_WORKER=claude
BRANCH=agent/demo-platform/issue-8
EOF

cat >"${platform_runs}/demo-platform-issue-8/runner.env" <<'EOF'
RUNNER_STATE=succeeded
LAST_EXIT_CODE=0
UPDATED_AT=2026-04-03T09:05:00Z
EOF

cat >"${platform_runs}/demo-platform-issue-8/result.env" <<'EOF'
OUTCOME=implemented
ACTION=host-publish-issue-pr
UPDATED_AT=2026-04-03T09:05:30Z
EOF

# History

cat >"${platform_history}/demo-platform-issue-7/run.env" <<'EOF'
TASK_KIND=issue
TASK_ID=7
SESSION=demo-platform-issue-7
MODE=safe
STARTED_AT=2026-04-02T20:00:00Z
CODING_WORKER=claude
EOF

cat >"${platform_history}/demo-platform-issue-7/runner.env" <<'EOF'
RUNNER_STATE=succeeded
LAST_EXIT_CODE=0
UPDATED_AT=2026-04-02T20:18:00Z
EOF

cat >"${platform_history}/demo-platform-issue-7/result.env" <<'EOF'
OUTCOME=implemented
ACTION=host-publish-issue-pr
UPDATED_AT=2026-04-02T20:18:30Z
EOF

cat >"${platform_history}/demo-platform-issue-6/run.env" <<'EOF'
TASK_KIND=issue
TASK_ID=6
SESSION=demo-platform-issue-6
MODE=safe
STARTED_AT=2026-04-02T16:30:00Z
CODING_WORKER=claude
EOF

cat >"${platform_history}/demo-platform-issue-6/runner.env" <<'EOF'
RUNNER_STATE=succeeded
LAST_EXIT_CODE=0
UPDATED_AT=2026-04-02T16:47:00Z
EOF

cat >"${platform_history}/demo-platform-issue-6/result.env" <<'EOF'
OUTCOME=reported
ACTION=host-comment-scheduled-report
UPDATED_AT=2026-04-02T16:47:30Z
EOF

# Controller

cat >"${platform_state}/resident-workers/issues/8/controller.env" <<'EOF'
ISSUE_ID=8
SESSION=demo-platform-issue-8
CONTROLLER_PID=99997
CONTROLLER_MODE=safe
CONTROLLER_LOOP_COUNT=2
CONTROLLER_STATE=stopped
CONTROLLER_REASON=session-succeeded
ACTIVE_RESIDENT_WORKER_KEY=issue-lane-recurring-general-claude-safe
ACTIVE_RESIDENT_LANE_KIND=recurring
ACTIVE_RESIDENT_LANE_VALUE=general
ACTIVE_PROVIDER_BACKEND=claude
ACTIVE_PROVIDER_MODEL=sonnet
PROVIDER_SWITCH_COUNT=0
PROVIDER_FAILOVER_COUNT=0
PROVIDER_WAIT_COUNT=0
UPDATED_AT=2026-04-03T09:05:30Z
EOF

cat >"${platform_state}/resident-workers/issues/issue-lane-recurring-general-claude-safe/metadata.env" <<'EOF'
RESIDENT_WORKER_KIND=issue
RESIDENT_WORKER_SCOPE=lane
RESIDENT_WORKER_KEY=issue-lane-recurring-general-claude-safe
ISSUE_ID=8
CODING_WORKER=claude
TASK_COUNT=8
LAST_STATUS=succeeded
LAST_STARTED_AT=2026-04-03T08:50:00Z
LAST_FINISHED_AT=2026-04-03T09:05:00Z
LAST_RUN_SESSION=demo-platform-issue-8
LAST_OUTCOME=implemented
LAST_ACTION=host-publish-issue-pr
EOF

cat >"${platform_state}/scheduled-issues/5.env" <<'EOF'
INTERVAL_SECONDS=3600
LAST_STARTED_AT=2026-04-03T08:00:00Z
NEXT_DUE_AT=2026-04-03T09:00:00Z
UPDATED_AT=2026-04-03T08:00:00Z
EOF

cat >"${platform_state}/resident-workers/issue-queue/pending/issue-11.env" <<'EOF'
ISSUE_ID=11
SESSION=demo-platform-issue-11
UPDATED_AT=2026-04-03T09:08:00Z
EOF

ACP_PROFILE_REGISTRY_ROOT="${profile_registry_root}" \
  python3 "${ROOT_DIR}/tools/dashboard/server.py" \
  --host 127.0.0.1 \
  --port "${port}" \
  >"${tmpdir}/server.log" 2>&1 &
server_pid="$!"

dashboard_url="http://127.0.0.1:${port}"

for _ in $(seq 1 40); do
  if curl -sf "${dashboard_url}/api/snapshot.json" >/dev/null 2>&1; then
    break
  fi
  sleep 0.25
done

if ! curl -sf "${dashboard_url}/api/snapshot.json" >/dev/null 2>&1; then
  cat "${tmpdir}/server.log" >&2
  echo "failed to start dashboard demo server" >&2
  exit 1
fi

cat >"${tmpdir}/capture-demo.js" <<'EOF'
const fs = require("fs");
const path = require("path");
const { chromium } = require(process.env.PLAYWRIGHT_PACKAGE_ROOT);

async function captureFrame(page, target, filename) {
  await page.evaluate((top) => window.scrollTo({ top, behavior: "instant" }), target);
  await page.waitForTimeout(350);
  await page.screenshot({ path: filename });
}

(async () => {
  const pngOut = process.env.ACP_PNG_OUT;
  const framesDir = process.env.ACP_FRAMES_DIR;
  const url = process.env.ACP_DEMO_URL;

  fs.mkdirSync(path.dirname(pngOut), { recursive: true });
  fs.mkdirSync(framesDir, { recursive: true });

  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({
    viewport: { width: 1440, height: 1080 },
    deviceScaleFactor: 1,
    colorScheme: "light",
  });

  await page.goto(url, { waitUntil: "networkidle" });
  await page.waitForTimeout(800);
  await page.screenshot({ path: pngOut, fullPage: true });

  // frame-00: global stats + first profile header
  await captureFrame(page, 0, path.join(framesDir, "frame-00.png"));
  // frame-01: scroll to active runs section
  await captureFrame(page, 650, path.join(framesDir, "frame-01.png"));
  // frame-02: recent completed runs + resident controllers
  await captureFrame(page, 1500, path.join(framesDir, "frame-02.png"));
  // frame-03: provider cooldowns + scheduled issues + queue
  await captureFrame(page, 2400, path.join(framesDir, "frame-03.png"));
  // frame-04: second profile (demo-platform)
  await captureFrame(page, 3400, path.join(framesDir, "frame-04.png"));
  // frame-05: back to top
  await captureFrame(page, 0, path.join(framesDir, "frame-05.png"));

  await browser.close();
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
EOF

PLAYWRIGHT_PACKAGE_ROOT="${PLAYWRIGHT_PACKAGE_ROOT}" \
ACP_DEMO_URL="${dashboard_url}" \
ACP_PNG_OUT="${PNG_OUT}" \
ACP_FRAMES_DIR="${frames_dir}" \
node "${tmpdir}/capture-demo.js"

ffmpeg \
  -y \
  -framerate 1.25 \
  -i "${frames_dir}/frame-%02d.png" \
  -vf "fps=10,scale=1200:-1:flags=lanczos,split[s0][s1];[s0]palettegen=stats_mode=diff[p];[s1][p]paletteuse=dither=bayer" \
  "${GIF_OUT}" \
  >/dev/null 2>&1

echo "DASHBOARD_DEMO_URL=${dashboard_url}"
echo "PNG_OUT=${PNG_OUT}"
echo "GIF_OUT=${GIF_OUT}"
