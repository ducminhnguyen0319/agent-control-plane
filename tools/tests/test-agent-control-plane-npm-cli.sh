#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLOW_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CLI_SCRIPT="${FLOW_ROOT}/npm/bin/agent-control-plane.js"
PACKAGE_VERSION="$(node -p "require('${FLOW_ROOT}/package.json').version")"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

platform_home="${tmpdir}/platform"
home_dir="${tmpdir}/home"
fake_bin="${tmpdir}/fake-bin"
mkdir -p "${platform_home}" "${home_dir}"
mkdir -p "${fake_bin}"

run_with_timeout() {
  local timeout_seconds="${1:?timeout required}"
  shift
  local python_bin
  python_bin="$(command -v python3 || true)"
  if [[ -z "${python_bin}" ]]; then
    echo "python3 is required for run_with_timeout" >&2
    return 127
  fi

  "${python_bin}" - "$timeout_seconds" "$@" <<'PY'
import os
import signal
import subprocess
import sys

timeout_seconds = float(sys.argv[1])
argv = sys.argv[2:]

proc = subprocess.Popen(argv, start_new_session=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

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
    sys.stdout.write(stdout)
    sys.stderr.write(stderr)
    sys.exit(124)

sys.stdout.write(stdout)
sys.stderr.write(stderr)
sys.exit(proc.returncode)
PY
}

cat >"${fake_bin}/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "auth" && "${2:-}" == "status" ]]; then
  echo "gh auth ok"
  exit 0
fi

if [[ "${1:-}" == "auth" && "${2:-}" == "login" ]]; then
  echo "gh auth login stub"
  exit 0
fi

echo "gh stub: unsupported invocation: $*" >&2
exit 0
EOF

cat >"${fake_bin}/jq" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat >"${fake_bin}/codex" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  echo "codex stub 0.0.0"
  exit 0
fi

if [[ "${1:-}" == "login" && "${2:-}" == "status" ]]; then
  echo "codex login ok"
  exit 0
fi

echo "codex stub"
exit 0
EOF

chmod +x "${fake_bin}/gh" "${fake_bin}/jq" "${fake_bin}/codex"

help_output="$(
  HOME="${home_dir}" \
  AGENT_PLATFORM_HOME="${platform_home}" \
  run_with_timeout 30 node "${CLI_SCRIPT}" help
)"

grep -q '^Usage:$' <<<"${help_output}"
grep -q '^  setup' <<<"${help_output}"
grep -q '^  sync' <<<"${help_output}"
grep -q '^  profile-smoke' <<<"${help_output}"
grep -q '^  launchd-install' <<<"${help_output}"
grep -q '^  remove' <<<"${help_output}"

version_output="$(
  HOME="${home_dir}" \
  AGENT_PLATFORM_HOME="${platform_home}" \
  run_with_timeout 30 node "${CLI_SCRIPT}" version
)"

grep -q "^${PACKAGE_VERSION}$" <<<"${version_output}"

HOME="${home_dir}" \
AGENT_PLATFORM_HOME="${platform_home}" \
run_with_timeout 30 node "${CLI_SCRIPT}" sync >/dev/null

test -f "${platform_home}/runtime-home/skills/openclaw/agent-control-plane/SKILL.md"
test -f "${platform_home}/runtime-home/tools/bin/flow-runtime-doctor.sh"
test -f "${platform_home}/runtime-home/skills/openclaw/agent-control-plane/tools/bin/codex-quota"
test -f "${platform_home}/runtime-home/skills/openclaw/agent-control-plane/tools/vendor/codex-quota-manager/scripts/auto-switch.sh"

doctor_output="$(
  HOME="${home_dir}" \
  AGENT_PLATFORM_HOME="${platform_home}" \
  run_with_timeout 30 node "${CLI_SCRIPT}" doctor
)"

grep -q '^CONTROL_PLANE_NAME=agent-control-plane$' <<<"${doctor_output}"
grep -q '^SOURCE_READY=yes$' <<<"${doctor_output}"

init_output="$(
  HOME="${home_dir}" \
  AGENT_PLATFORM_HOME="${platform_home}" \
  run_with_timeout 30 node "${CLI_SCRIPT}" init \
    --profile-id alpha \
    --repo-slug example-owner/alpha \
    --allow-missing-repo \
    --skip-anchor-sync \
    --skip-workspace-sync
)"

grep -q '^PROJECT_INIT_STATUS=ok$' <<<"${init_output}"
grep -q '^PROFILE_ID=alpha$' <<<"${init_output}"
grep -q "^RUNTIME_HOME=${platform_home}/runtime-home$" <<<"${init_output}"

profile_smoke_output="$(
  HOME="${home_dir}" \
  AGENT_PLATFORM_HOME="${platform_home}" \
  run_with_timeout 30 node "${CLI_SCRIPT}" profile-smoke --profile-id alpha
)"

grep -q '^PROFILE_ID=alpha$' <<<"${profile_smoke_output}"
grep -q '^PROFILE_STATUS=ok$' <<<"${profile_smoke_output}"

runtime_status_output="$(
  HOME="${home_dir}" \
  AGENT_PLATFORM_HOME="${platform_home}" \
  run_with_timeout 30 node "${CLI_SCRIPT}" runtime status --profile-id alpha
)"

grep -q '^PROFILE_ID=alpha$' <<<"${runtime_status_output}"
grep -q "^CONFIG_YAML=${platform_home}/control-plane/profiles/alpha/control-plane.yaml$" <<<"${runtime_status_output}"

runtime_state_root="$(awk -F= '/^STATE_ROOT=/{print $2; exit}' <<<"${runtime_status_output}")"
runtime_bootstrap_log="${runtime_state_root}/bootstrap-source.log"
runtime_bootstrap_path="${tmpdir}/fake-runtime-bootstrap.sh"
mkdir -p "${runtime_state_root}"

HOME="${home_dir}" \
AGENT_PLATFORM_HOME="${platform_home}" \
ACP_PROJECT_RUNTIME_LAUNCHCTL_BIN="/nonexistent" \
run_with_timeout 30 node "${CLI_SCRIPT}" runtime stop --profile-id alpha --wait-seconds 1 >/dev/null || true

cat >"${runtime_bootstrap_path}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'bootstrapped-from=%s\n' "\$0" >>"${runtime_bootstrap_log}"
mkdir -p "${runtime_state_root}/heartbeat-loop.lock"
sleep 60 >/dev/null 2>&1 &
child_pid="\$!"
printf '%s\n' "\$child_pid" >"${runtime_state_root}/heartbeat-loop.lock/pid"
wait "\$child_pid"
EOF
chmod +x "${runtime_bootstrap_path}"

cat >"${fake_bin}/kick-start-runtime.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'KICK_STATUS=scheduled\nPID=12345\n'
EOF
chmod +x "${fake_bin}/kick-start-runtime.sh"

runtime_start_output="$(
  HOME="${home_dir}" \
  AGENT_PLATFORM_HOME="${platform_home}" \
  ACP_PROJECT_RUNTIME_BOOTSTRAP_SCRIPT="${runtime_bootstrap_path}" \
  ACP_PROJECT_RUNTIME_KICK_SCRIPT="${fake_bin}/kick-start-runtime.sh" \
  ACP_PROJECT_RUNTIME_LAUNCHCTL_BIN="/nonexistent" \
  ACP_PROJECT_RUNTIME_START_WAIT_SECONDS=1 \
  run_with_timeout 30 node "${CLI_SCRIPT}" runtime start --profile-id alpha
)"

grep -q '^ACTION=start$' <<<"${runtime_start_output}"
grep -q '^START_MODE=kick-scheduler-fallback-supervisor$' <<<"${runtime_start_output}"
grep -q '^FALLBACK_SUPERVISOR_LOG=' <<<"${runtime_start_output}"

for _ in 1 2 3 4 5; do
  if [[ -f "${runtime_bootstrap_log}" ]] && grep -q "^bootstrapped-from=${runtime_bootstrap_path}\$" "${runtime_bootstrap_log}"; then
    break
  fi
  sleep 1
done

grep -q "^bootstrapped-from=${runtime_bootstrap_path}\$" "${runtime_bootstrap_log}"

HOME="${home_dir}" \
AGENT_PLATFORM_HOME="${platform_home}" \
ACP_PROJECT_RUNTIME_BOOTSTRAP_SCRIPT="${runtime_bootstrap_path}" \
ACP_PROJECT_RUNTIME_KICK_SCRIPT="${fake_bin}/kick-start-runtime.sh" \
ACP_PROJECT_RUNTIME_LAUNCHCTL_BIN="/nonexistent" \
run_with_timeout 30 node "${CLI_SCRIPT}" runtime stop --profile-id alpha --wait-seconds 1 >/dev/null

launchd_help="$(
  HOME="${home_dir}" \
  AGENT_PLATFORM_HOME="${platform_home}" \
  run_with_timeout 30 node "${CLI_SCRIPT}" launchd-install --help
)"

grep -q '^Usage:$' <<<"${launchd_help}"

remove_help="$(
  HOME="${home_dir}" \
  AGENT_PLATFORM_HOME="${platform_home}" \
  run_with_timeout 30 node "${CLI_SCRIPT}" remove --help
)"

grep -q '^Usage:$' <<<"${remove_help}"

setup_help="$(
  HOME="${home_dir}" \
  AGENT_PLATFORM_HOME="${platform_home}" \
  run_with_timeout 30 node "${CLI_SCRIPT}" setup --help
)"

grep -q -- '--install-missing-deps' <<<"${setup_help}"
grep -q -- '--no-install-missing-deps' <<<"${setup_help}"
grep -q -- '--install-missing-backend' <<<"${setup_help}"
grep -q -- '--no-install-missing-backend' <<<"${setup_help}"
grep -q -- '--gh-auth-login' <<<"${setup_help}"
grep -q -- '--no-gh-auth-login' <<<"${setup_help}"
grep -q -- '--dry-run' <<<"${setup_help}"
grep -q -- '--plan' <<<"${setup_help}"
grep -q -- '--json' <<<"${setup_help}"

setup_repo="${tmpdir}/setup-demo"
mkdir -p "${setup_repo}"
git -C "${setup_repo}" init -q -b main
git -C "${setup_repo}" config user.name "ACP Test"
git -C "${setup_repo}" config user.email "acp-test@example.com"
printf '# setup demo\n' >"${setup_repo}/README.md"
git -C "${setup_repo}" add README.md
git -C "${setup_repo}" commit -q -m "init"
git -C "${setup_repo}" remote add origin "https://github.com/example-owner/setup-demo.git"

setup_output="$(
  HOME="${home_dir}" \
  AGENT_PLATFORM_HOME="${platform_home}" \
  PATH="${fake_bin}:${PATH}" \
  run_with_timeout 30 node "${CLI_SCRIPT}" setup \
    --non-interactive \
    --repo-root "${setup_repo}" \
    --no-start-runtime \
    --skip-anchor-sync \
    --skip-workspace-sync
)"

grep -q '^SETUP_STATUS=ok$' <<<"${setup_output}"
grep -q '^PROFILE_ID=setup-demo$' <<<"${setup_output}"
grep -q '^REPO_SLUG=example-owner/setup-demo$' <<<"${setup_output}"
grep -q '^CODING_WORKER=' <<<"${setup_output}"
grep -q '^CORE_TOOLS_STATUS=ok$' <<<"${setup_output}"
grep -q '^WORKER_BACKEND_COMMAND=' <<<"${setup_output}"
grep -q '^WORKER_BACKEND_STATUS=ok$' <<<"${setup_output}"
grep -q '^WORKER_SETUP_GUIDE_STATUS=' <<<"${setup_output}"
grep -q '^WORKER_BACKEND_INSTALL_STATUS=' <<<"${setup_output}"
grep -q '^WORKER_SETUP_DOCS_OPENED=' <<<"${setup_output}"
grep -q '^WORKER_BACKEND_DOCS_URL=' <<<"${setup_output}"
grep -q '^WORKER_BACKEND_AUTH_EXAMPLE=' <<<"${setup_output}"
grep -q '^WORKER_BACKEND_VERIFY_EXAMPLE=' <<<"${setup_output}"
grep -q '^GITHUB_AUTH_STATUS=' <<<"${setup_output}"
grep -q '^FINAL_FIXUP_STATUS=' <<<"${setup_output}"
grep -q '^FINAL_FIXUP_ACTIONS=' <<<"${setup_output}"
grep -q '^DEPENDENCY_INSTALL_STATUS=' <<<"${setup_output}"
grep -q '^GITHUB_AUTH_STEP_STATUS=' <<<"${setup_output}"
grep -q '^PROJECT_INIT_STATUS=ok$' <<<"${setup_output}"
grep -q '^DOCTOR_STATUS=ok$' <<<"${setup_output}"
grep -q '^RUNTIME_START_STATUS=skipped$' <<<"${setup_output}"
grep -q '^RUNTIME_START_REASON=not-requested$' <<<"${setup_output}"
test -f "${platform_home}/control-plane/profiles/setup-demo/control-plane.yaml"
test -d "${platform_home}/projects/setup-demo/repo"

custom_agent_root="${tmpdir}/custom-agent-root"
custom_agent_repo_root="${tmpdir}/custom-anchor-repo"
custom_worktree_root="${tmpdir}/custom-worktrees"

setup_custom_output="$(
  HOME="${home_dir}" \
  AGENT_PLATFORM_HOME="${platform_home}" \
  PATH="${fake_bin}:${PATH}" \
  run_with_timeout 30 node "${CLI_SCRIPT}" setup \
    --non-interactive \
    --repo-root "${setup_repo}" \
    --profile-id setup-custom \
    --agent-root "${custom_agent_root}" \
    --agent-repo-root "${custom_agent_repo_root}" \
    --worktree-root "${custom_worktree_root}" \
    --no-start-runtime \
    --skip-anchor-sync \
    --skip-workspace-sync
)"

grep -q '^SETUP_STATUS=ok$' <<<"${setup_custom_output}"
grep -q '^PROFILE_ID=setup-custom$' <<<"${setup_custom_output}"
grep -q "^AGENT_REPO_ROOT=${custom_agent_repo_root}$" <<<"${setup_custom_output}"
grep -q '^ANCHOR_SYNC_STATUS=skipped$' <<<"${setup_custom_output}"
test -f "${platform_home}/control-plane/profiles/setup-custom/control-plane.yaml"
test -d "${custom_agent_root}"
test -d "${custom_agent_repo_root}"
test -d "${custom_worktree_root}"

setup_deferred_output="$(
  HOME="${home_dir}" \
  AGENT_PLATFORM_HOME="${platform_home}" \
  PATH="${fake_bin}:${PATH}" \
  run_with_timeout 30 node "${CLI_SCRIPT}" setup \
    --non-interactive \
    --repo-root "${setup_repo}" \
    --profile-id deferred-demo \
    --no-start-runtime \
    --skip-workspace-sync
)"

grep -q '^SETUP_STATUS=ok$' <<<"${setup_deferred_output}"
grep -q '^PROFILE_ID=deferred-demo$' <<<"${setup_deferred_output}"
grep -q '^ANCHOR_SYNC_STATUS=deferred$' <<<"${setup_deferred_output}"
grep -q '^ANCHOR_SYNC_REASON=' <<<"${setup_deferred_output}"
grep -q '^PROJECT_INIT_STATUS=ok$' <<<"${setup_deferred_output}"
grep -q '^DOCTOR_STATUS=ok$' <<<"${setup_deferred_output}"
test -f "${platform_home}/control-plane/profiles/deferred-demo/control-plane.yaml"

setup_dry_run_output="$(
  HOME="${home_dir}" \
  AGENT_PLATFORM_HOME="${platform_home}" \
  PATH="${fake_bin}:${PATH}" \
  run_with_timeout 30 node "${CLI_SCRIPT}" setup \
    --dry-run \
    --non-interactive \
    --repo-root "${setup_repo}" \
    --no-start-runtime \
    --skip-anchor-sync \
    --skip-workspace-sync
)"

grep -q '^SETUP_STATUS=dry-run$' <<<"${setup_dry_run_output}"
grep -q '^SETUP_MODE=dry-run$' <<<"${setup_dry_run_output}"
grep -q '^PROJECT_INIT_STATUS=would-run$' <<<"${setup_dry_run_output}"
grep -q '^DOCTOR_STATUS=would-run$' <<<"${setup_dry_run_output}"
grep -q '^FINAL_FIXUP_STATUS=planned$' <<<"${setup_dry_run_output}"
grep -q '^FINAL_FIXUP_ACTIONS=review-plan$' <<<"${setup_dry_run_output}"

setup_json_output="$(
  HOME="${home_dir}" \
  AGENT_PLATFORM_HOME="${platform_home}" \
  PATH="${fake_bin}:${PATH}" \
  run_with_timeout 30 node "${CLI_SCRIPT}" setup \
    --json \
    --repo-root "${setup_repo}" \
    --profile-id setup-json \
    --no-start-runtime \
    --skip-anchor-sync \
    --skip-workspace-sync
)"

printf '%s' "${setup_json_output}" | node -e '
  const fs = require("fs");
  const data = JSON.parse(fs.readFileSync(0, "utf8"));
  if (data.setupStatus !== "ok") process.exit(1);
  if (data.setupMode !== "run") process.exit(1);
  if (data.profileId !== "setup-json") process.exit(1);
  if (data.projectInitStatus !== "ok") process.exit(1);
  if (data.doctorStatus !== "ok") process.exit(1);
  if (!data.workerBackend || !data.githubAuth || !data.finalFixup) process.exit(1);
'

setup_deferred_json_output="$(
  HOME="${home_dir}" \
  AGENT_PLATFORM_HOME="${platform_home}" \
  PATH="${fake_bin}:${PATH}" \
  run_with_timeout 30 node "${CLI_SCRIPT}" setup \
    --json \
    --repo-root "${setup_repo}" \
    --profile-id deferred-json \
    --no-start-runtime \
    --skip-workspace-sync
)"

printf '%s' "${setup_deferred_json_output}" | node -e '
  const fs = require("fs");
  const data = JSON.parse(fs.readFileSync(0, "utf8"));
  if (data.setupStatus !== "ok") process.exit(1);
  if (!data.anchorSync) process.exit(1);
  if (data.anchorSync.status !== "deferred") process.exit(1);
  if (!data.anchorSync.reason) process.exit(1);
  if (data.projectInitStatus !== "ok") process.exit(1);
'

setup_dry_run_json_output="$(
  HOME="${home_dir}" \
  AGENT_PLATFORM_HOME="${platform_home}" \
  PATH="${fake_bin}:${PATH}" \
  run_with_timeout 30 node "${CLI_SCRIPT}" setup \
    --json \
    --dry-run \
    --repo-root "${setup_repo}" \
    --profile-id dry-run-json \
    --no-start-runtime \
    --skip-anchor-sync \
    --skip-workspace-sync
)"

printf '%s' "${setup_dry_run_json_output}" | node -e '
  const fs = require("fs");
  const data = JSON.parse(fs.readFileSync(0, "utf8"));
  if (data.setupStatus !== "dry-run") process.exit(1);
  if (data.setupMode !== "dry-run") process.exit(1);
  if (data.profileId !== "dry-run-json") process.exit(1);
  if (data.projectInitStatus !== "would-run") process.exit(1);
  if (data.doctorStatus !== "would-run") process.exit(1);
  if (!data.finalFixup || data.finalFixup.status !== "planned") process.exit(1);
  if (data.dependencyInstall && data.dependencyInstall.status === "not-needed" && data.dependencyInstall.command !== "") process.exit(1);
  if (data.workerBackend && data.workerBackend.installStatus === "not-needed" && data.workerBackend.installCommand !== "") process.exit(1);
'

test ! -e "${platform_home}/control-plane/profiles/dry-run-json/control-plane.yaml"

apk_bin="${tmpdir}/apk-bin"
mkdir -p "${apk_bin}"
cat >"${apk_bin}/bash" <<'EOF'
#!/bin/sh
exec /bin/bash "$@"
EOF
cat >"${apk_bin}/apk" <<'EOF'
#!/bin/sh
echo "apk stub"
exit 0
EOF
chmod +x "${apk_bin}/bash" "${apk_bin}/apk"
apk_home="${tmpdir}/apk-home"
mkdir -p "${apk_home}"
cat >"${apk_home}/.bash_profile" <<EOF
export PATH="${apk_bin}"
EOF

setup_apk_dry_run_output="$(
  AGENT_PLATFORM_HOME="${platform_home}" \
  HOME="${apk_home}" \
  PATH="${apk_bin}:${PATH}" \
  run_with_timeout 30 node "${CLI_SCRIPT}" setup \
    --json \
    --dry-run \
    --non-interactive \
    --repo-root "${setup_repo}" \
    --repo-slug test-owner/alpine-distro \
    --no-start-runtime \
    --skip-anchor-sync \
    --skip-workspace-sync
)"

printf '%s' "${setup_apk_dry_run_output}" | node -e '
  const fs = require("fs");
  const data = JSON.parse(fs.readFileSync(0, "utf8"));
  if (data.setupStatus !== "dry-run") process.exit(1);
  if (data.dependencyInstall.status !== "would-prompt") process.exit(1);
  if (data.dependencyInstall.installer !== "apk") process.exit(1);
  if (!data.dependencyInstall.command.includes("apk")) process.exit(1);
'

# onboard alias maps to setup
onboard_output="$(
  HOME="${home_dir}" \
  AGENT_PLATFORM_HOME="${platform_home}" \
  PATH="${fake_bin}:${PATH}" \
  run_with_timeout 30 node "${CLI_SCRIPT}" onboard \
    --non-interactive \
    --repo-root "${setup_repo}" \
    --profile-id onboard-alias-demo \
    --no-start-runtime \
    --skip-anchor-sync \
    --skip-workspace-sync
)"
grep -q '^SETUP_STATUS=ok$' <<<"${onboard_output}"
grep -q '^PROFILE_ID=onboard-alias-demo$' <<<"${onboard_output}"
test -f "${platform_home}/control-plane/profiles/onboard-alias-demo/control-plane.yaml"

# onboard shows in help output
help_onboard_output="$(
  HOME="${home_dir}" \
  AGENT_PLATFORM_HOME="${platform_home}" \
  run_with_timeout 30 node "${CLI_SCRIPT}" help
)"
grep -q 'onboard' <<<"${help_onboard_output}"

# openclaw worker setup outputs OPENROUTER_API_KEY warning when key is absent
openclaw_setup_output="$(
  HOME="${home_dir}" \
  AGENT_PLATFORM_HOME="${platform_home}" \
  PATH="${fake_bin}:${PATH}" \
  OPENROUTER_API_KEY="" \
  run_with_timeout 30 node "${CLI_SCRIPT}" setup \
    --non-interactive \
    --repo-root "${setup_repo}" \
    --profile-id openclaw-key-check \
    --coding-worker openclaw \
    --no-start-runtime \
    --skip-anchor-sync \
    --skip-workspace-sync
)"
grep -q '^SETUP_STATUS=ok$' <<<"${openclaw_setup_output}"
grep -q 'OPENROUTER_API_KEY' <<<"${openclaw_setup_output}"
