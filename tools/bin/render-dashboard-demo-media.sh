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
profile_dir="${profile_registry_root}/demo-retail"
runs_root="${tmpdir}/runtime/demo-retail/runs"
state_root="${tmpdir}/runtime/demo-retail/state"
frames_dir="${tmpdir}/frames"
mkdir -p \
  "${profile_dir}" \
  "${runs_root}/demo-issue-14" \
  "${runs_root}/demo-issue-17" \
  "${runs_root}/demo-issue-21" \
  "${state_root}/resident-workers/issues/14" \
  "${state_root}/resident-workers/issues/issue-lane-recurring-general-openclaw-safe" \
  "${state_root}/retries/providers" \
  "${state_root}/scheduled-issues" \
  "${state_root}/resident-workers/issue-queue/pending" \
  "${frames_dir}" \
  "${OUTPUT_DIR}"

sleep 600 &
controller_pid="$!"

cat >"${profile_dir}/control-plane.yaml" <<EOF
schema_version: "1"
id: "demo-retail"
repo:
  slug: "example/retail-agent-demo"
  root: "${tmpdir}/repo"
  default_branch: "main"
runtime:
  orchestrator_agent_root: "${tmpdir}/runtime/demo-retail"
  worktree_root: "${tmpdir}/worktrees"
  agent_repo_root: "${tmpdir}/repo"
  runs_root: "${runs_root}"
  state_root: "${state_root}"
  history_root: "${tmpdir}/runtime/demo-retail/history"
  retained_repo_root: "${tmpdir}/repo"
  vscode_workspace_file: "${tmpdir}/demo-retail.code-workspace"
session_naming:
  issue_prefix: "demo-issue-"
  pr_prefix: "demo-pr-"
execution:
  coding_worker: "openclaw"
  openclaw:
    model: "openrouter/sonic"
    thinking: "adaptive"
    timeout_seconds: 900
EOF

cat >"${runs_root}/demo-issue-14/run.env" <<'EOF'
TASK_KIND=issue
TASK_ID=14
SESSION=demo-issue-14
MODE=safe
STARTED_AT=2026-03-27T15:00:00Z
CODING_WORKER=openclaw
WORKTREE=/tmp/demo-worktree-14
BRANCH=agent/demo/issue-14
RESIDENT_WORKER_KEY=issue-lane-recurring-general-openclaw-safe
OPENCLAW_MODEL=openrouter/sonic
EOF

cat >"${runs_root}/demo-issue-14/runner.env" <<'EOF'
RUNNER_STATE=succeeded
THREAD_ID=thread-demo-14
LAST_EXIT_CODE=0
UPDATED_AT=2026-03-27T15:04:00Z
EOF

cat >"${runs_root}/demo-issue-14/result.env" <<'EOF'
OUTCOME=implemented
ACTION=host-publish-issue-pr
EOF

cat >"${runs_root}/demo-issue-17/run.env" <<'EOF'
TASK_KIND=issue
TASK_ID=17
SESSION=demo-issue-17
MODE=safe
STARTED_AT=2026-03-27T15:05:00Z
CODING_WORKER=openclaw
WORKTREE=/tmp/demo-worktree-17
BRANCH=agent/demo/issue-17
OPENCLAW_MODEL=openrouter/sonic
EOF

cat >"${runs_root}/demo-issue-17/runner.env" <<'EOF'
RUNNER_STATE=succeeded
THREAD_ID=thread-demo-17
LAST_EXIT_CODE=0
UPDATED_AT=2026-03-27T15:08:00Z
EOF

cat >"${runs_root}/demo-issue-17/result.env" <<'EOF'
OUTCOME=reported
ACTION=host-comment-scheduled-report
EOF

cat >"${runs_root}/demo-issue-21/run.env" <<'EOF'
TASK_KIND=issue
TASK_ID=21
SESSION=demo-issue-21
MODE=safe
STARTED_AT=2026-03-27T15:10:00Z
CODING_WORKER=openclaw
WORKTREE=/tmp/demo-worktree-21
BRANCH=agent/demo/issue-21
OPENCLAW_MODEL=openrouter/sonic
EOF

cat >"${runs_root}/demo-issue-21/runner.env" <<'EOF'
RUNNER_STATE=succeeded
THREAD_ID=thread-demo-21
LAST_EXIT_CODE=0
UPDATED_AT=2026-03-27T15:12:00Z
EOF

cat >"${runs_root}/demo-issue-21/result.env" <<'EOF'
OUTCOME=blocked
ACTION=host-comment-blocked
FAILURE_REASON=provider-quota-limit
EOF

cat >"${state_root}/resident-workers/issues/14/controller.env" <<EOF
ISSUE_ID=14
SESSION=demo-issue-14
CONTROLLER_PID=${controller_pid}
CONTROLLER_MODE=safe
CONTROLLER_LOOP_COUNT=4
CONTROLLER_STATE=waiting-provider
CONTROLLER_REASON=provider-cooldown
ACTIVE_RESIDENT_WORKER_KEY=issue-lane-recurring-general-openclaw-safe
ACTIVE_RESIDENT_LANE_KIND=recurring
ACTIVE_RESIDENT_LANE_VALUE=general
ACTIVE_PROVIDER_BACKEND=openclaw
ACTIVE_PROVIDER_MODEL=openrouter/sonic
PROVIDER_SWITCH_COUNT=1
PROVIDER_FAILOVER_COUNT=1
PROVIDER_WAIT_COUNT=2
PROVIDER_WAIT_TOTAL_SECONDS=45
PROVIDER_LAST_WAIT_SECONDS=21
UPDATED_AT=2026-03-27T15:13:00Z
EOF

cat >"${state_root}/resident-workers/issues/issue-lane-recurring-general-openclaw-safe/metadata.env" <<'EOF'
RESIDENT_WORKER_KIND=issue
RESIDENT_WORKER_SCOPE=lane
RESIDENT_WORKER_KEY=issue-lane-recurring-general-openclaw-safe
ISSUE_ID=14
CODING_WORKER=openclaw
TASK_COUNT=9
LAST_STATUS=running
LAST_STARTED_AT=2026-03-27T15:00:00Z
LAST_RUN_SESSION=demo-issue-14
LAST_OUTCOME=implemented
LAST_ACTION=host-publish-issue-pr
EOF

cat >"${state_root}/retries/providers/openclaw-openrouter-sonic.env" <<'EOF'
ATTEMPTS=2
NEXT_ATTEMPT_EPOCH=4102444800
NEXT_ATTEMPT_AT=2100-01-01T00:00:00Z
LAST_REASON=provider-quota-limit
UPDATED_AT=2026-03-27T15:14:00Z
EOF

cat >"${state_root}/scheduled-issues/17.env" <<'EOF'
INTERVAL_SECONDS=1800
LAST_STARTED_AT=2026-03-27T15:05:00Z
NEXT_DUE_AT=2026-03-27T15:35:00Z
UPDATED_AT=2026-03-27T15:05:00Z
EOF

cat >"${state_root}/scheduled-issues/44.env" <<'EOF'
INTERVAL_SECONDS=3600
LAST_STARTED_AT=2026-03-27T14:30:00Z
NEXT_DUE_AT=2026-03-27T15:30:00Z
UPDATED_AT=2026-03-27T14:30:00Z
EOF

cat >"${state_root}/resident-workers/issue-queue/pending/issue-27.env" <<'EOF'
ISSUE_ID=27
SESSION=demo-issue-27
UPDATED_AT=2026-03-27T15:14:00Z
EOF

cat >"${state_root}/resident-workers/issue-queue/pending/issue-28.env" <<'EOF'
ISSUE_ID=28
SESSION=demo-issue-28
UPDATED_AT=2026-03-27T15:15:00Z
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

  await captureFrame(page, 0, path.join(framesDir, "frame-00.png"));
  await page.click("#refresh-button");
  await page.waitForTimeout(500);
  await captureFrame(page, 0, path.join(framesDir, "frame-01.png"));
  await captureFrame(page, 900, path.join(framesDir, "frame-02.png"));
  await captureFrame(page, 1700, path.join(framesDir, "frame-03.png"));
  await captureFrame(page, 0, path.join(framesDir, "frame-04.png"));

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
