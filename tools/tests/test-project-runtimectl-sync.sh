#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNTIMECTL_BIN="${FLOW_ROOT}/tools/bin/project-runtimectl.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

profile_registry_root="${tmpdir}/profiles"
profile_dir="${profile_registry_root}/demo"
runtime_root="${tmpdir}/runtime/demo"
state_root="${runtime_root}/state"
runtime_home="${tmpdir}/runtime-home"
source_home="${tmpdir}/source-home"
ensure_sync_script="${tmpdir}/ensure-sync.sh"
ensure_log="${tmpdir}/ensure.log"

mkdir -p "${profile_dir}" "${runtime_root}" "${runtime_home}" "${source_home}"

cat >"${profile_dir}/control-plane.yaml" <<EOF
schema_version: "1"
id: "demo"
repo:
  slug: "example/demo"
  root: "${tmpdir}/repo"
  default_branch: "main"
runtime:
  orchestrator_agent_root: "${runtime_root}"
  worktree_root: "${tmpdir}/worktrees"
  agent_repo_root: "${tmpdir}/repo"
  runs_root: "${runtime_root}/runs"
  state_root: "${state_root}"
  history_root: "${runtime_root}/history"
  retained_repo_root: "${tmpdir}/repo"
  vscode_workspace_file: "${tmpdir}/demo.code-workspace"
execution:
  coding_worker: "openclaw"
  openclaw:
    model: "primary/model"
    thinking: "adaptive"
    timeout_seconds: 900
EOF

cat >"${ensure_sync_script}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'ARGS=%s\n' "$*" >"${ACP_TEST_ENSURE_LOG}"
force_value="no"
if [[ "$*" == *"--force"* ]]; then
  force_value="yes"
fi
runtime_home=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --runtime-home) runtime_home="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done
mkdir -p "${runtime_home}"
cat >"${runtime_home}/.agent-control-plane-runtime-sync.env" <<STAMP
SOURCE_HOME='stub-source'
SOURCE_SKILL_DIR='stub-skill'
RUNTIME_HOME='${runtime_home}'
RUNTIME_SKILL_DIR='${runtime_home}/skills/openclaw/agent-control-plane'
SOURCE_FINGERPRINT='abc123'
SYNC_STATUS='updated'
UPDATED_AT='2026-04-02T13:33:00Z'
STAMP
printf 'SYNC_STATUS=updated\n'
printf 'SOURCE_HOME=stub-source\n'
printf 'RUNTIME_HOME=%s\n' "${runtime_home}"
printf 'SOURCE_FINGERPRINT=abc123\n'
printf 'FORCE_USED=%s\n' "${force_value}"
EOF
chmod +x "${ensure_sync_script}"

sync_output="$(
  ACP_PROFILE_REGISTRY_ROOT="${profile_registry_root}" \
  ACP_PROJECT_RUNTIME_RUNTIME_HOME="${runtime_home}" \
  ACP_PROJECT_RUNTIME_SOURCE_HOME="${source_home}" \
  ACP_PROJECT_RUNTIME_ENSURE_SYNC_SCRIPT="${ensure_sync_script}" \
  ACP_TEST_ENSURE_LOG="${ensure_log}" \
    bash "${RUNTIMECTL_BIN}" sync --profile-id demo --force
)"

grep -q '^ACTION=sync$' <<<"${sync_output}"
grep -q '^PROFILE_ID=demo$' <<<"${sync_output}"
grep -q '^SYNC_STATUS=updated$' <<<"${sync_output}"
grep -q '^FORCE_USED=yes$' <<<"${sync_output}"
grep -q -- "--source-home ${source_home}" "${ensure_log}"
grep -q -- "--runtime-home ${runtime_home}" "${ensure_log}"
grep -q -- "--force" "${ensure_log}"

sync_output_no_override="$(
  ACP_PROFILE_REGISTRY_ROOT="${profile_registry_root}" \
  ACP_PROJECT_RUNTIME_RUNTIME_HOME="${runtime_home}" \
  ACP_PROJECT_RUNTIME_ENSURE_SYNC_SCRIPT="${ensure_sync_script}" \
  ACP_TEST_ENSURE_LOG="${ensure_log}" \
    bash "${RUNTIMECTL_BIN}" sync --profile-id demo
)"

grep -q '^ACTION=sync$' <<<"${sync_output_no_override}"
grep -q '^SYNC_STATUS=updated$' <<<"${sync_output_no_override}"
grep -q '^FORCE_USED=no$' <<<"${sync_output_no_override}"
grep -q '^ARGS=--runtime-home '"${runtime_home}"'$' "${ensure_log}"
if grep -q -- '--source-home' "${ensure_log}"; then
  echo "project runtimectl passed unexpected source-home override" >&2
  exit 1
fi

status_output="$(
  ACP_PROFILE_REGISTRY_ROOT="${profile_registry_root}" \
  ACP_PROJECT_RUNTIME_RUNTIME_HOME="${runtime_home}" \
    bash "${RUNTIMECTL_BIN}" status --profile-id demo
)"

grep -q '^SYNC_STAMP_FILE='"${runtime_home}"'/.agent-control-plane-runtime-sync.env$' <<<"${status_output}"
grep -q '^RUNTIME_SYNC_STATUS=updated$' <<<"${status_output}"
grep -q '^RUNTIME_SYNC_UPDATED_AT=2026-04-02T13:33:00Z$' <<<"${status_output}"
grep -q '^RUNTIME_SYNC_FINGERPRINT=abc123$' <<<"${status_output}"

echo "project runtimectl sync test passed"
