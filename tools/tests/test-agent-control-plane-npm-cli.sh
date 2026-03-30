#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLOW_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CLI_SCRIPT="${FLOW_ROOT}/npm/bin/agent-control-plane.js"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

platform_home="${tmpdir}/platform"
home_dir="${tmpdir}/home"
mkdir -p "${platform_home}" "${home_dir}"

help_output="$(
  HOME="${home_dir}" \
  AGENT_PLATFORM_HOME="${platform_home}" \
  node "${CLI_SCRIPT}" help
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
  node "${CLI_SCRIPT}" version
)"

grep -q '^0\.1\.0$' <<<"${version_output}"

HOME="${home_dir}" \
AGENT_PLATFORM_HOME="${platform_home}" \
node "${CLI_SCRIPT}" sync >/dev/null

test -f "${platform_home}/runtime-home/skills/openclaw/agent-control-plane/SKILL.md"
test -f "${platform_home}/runtime-home/tools/bin/flow-runtime-doctor.sh"
test -f "${platform_home}/runtime-home/skills/openclaw/agent-control-plane/tools/bin/codex-quota"
test -f "${platform_home}/runtime-home/skills/openclaw/agent-control-plane/tools/vendor/codex-quota-manager/scripts/auto-switch.sh"

doctor_output="$(
  HOME="${home_dir}" \
  AGENT_PLATFORM_HOME="${platform_home}" \
  node "${CLI_SCRIPT}" doctor
)"

grep -q '^CONTROL_PLANE_NAME=agent-control-plane$' <<<"${doctor_output}"
grep -q '^SOURCE_READY=yes$' <<<"${doctor_output}"

init_output="$(
  HOME="${home_dir}" \
  AGENT_PLATFORM_HOME="${platform_home}" \
  node "${CLI_SCRIPT}" init \
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
  node "${CLI_SCRIPT}" profile-smoke --profile-id alpha
)"

grep -q '^PROFILE_ID=alpha$' <<<"${profile_smoke_output}"
grep -q '^PROFILE_STATUS=ok$' <<<"${profile_smoke_output}"

runtime_status_output="$(
  HOME="${home_dir}" \
  AGENT_PLATFORM_HOME="${platform_home}" \
  node "${CLI_SCRIPT}" runtime status --profile-id alpha
)"

grep -q '^PROFILE_ID=alpha$' <<<"${runtime_status_output}"
grep -q "^CONFIG_YAML=${platform_home}/control-plane/profiles/alpha/control-plane.yaml$" <<<"${runtime_status_output}"

launchd_help="$(
  HOME="${home_dir}" \
  AGENT_PLATFORM_HOME="${platform_home}" \
  node "${CLI_SCRIPT}" launchd-install --help
)"

grep -q '^Usage:$' <<<"${launchd_help}"

remove_help="$(
  HOME="${home_dir}" \
  AGENT_PLATFORM_HOME="${platform_home}" \
  node "${CLI_SCRIPT}" remove --help
)"

grep -q '^Usage:$' <<<"${remove_help}"

setup_help="$(
  HOME="${home_dir}" \
  AGENT_PLATFORM_HOME="${platform_home}" \
  node "${CLI_SCRIPT}" setup --help
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
  node "${CLI_SCRIPT}" setup \
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

setup_dry_run_output="$(
  HOME="${home_dir}" \
  AGENT_PLATFORM_HOME="${platform_home}" \
  node "${CLI_SCRIPT}" setup \
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
  node "${CLI_SCRIPT}" setup \
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

setup_dry_run_json_output="$(
  HOME="${home_dir}" \
  AGENT_PLATFORM_HOME="${platform_home}" \
  node "${CLI_SCRIPT}" setup \
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
