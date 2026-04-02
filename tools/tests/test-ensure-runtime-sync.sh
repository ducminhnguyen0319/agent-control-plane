#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENSURE_BIN="${FLOW_ROOT}/tools/bin/ensure-runtime-sync.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

source_home="${tmpdir}/source-home"
runtime_home="${tmpdir}/runtime-home"
sync_script="${tmpdir}/sync.sh"
sync_log="${tmpdir}/sync.log"
skill_root="${source_home}/skills/openclaw/agent-control-plane"

mkdir -p "${source_home}/tools/bin" "${source_home}/skills/openclaw/codex-quota-manager" "${skill_root}/tools/bin"
printf 'one\n' >"${source_home}/tools/bin/example.sh"
printf 'two\n' >"${skill_root}/tools/bin/example.sh"
printf '# test skill\n' >"${skill_root}/SKILL.md"

cat >"${sync_script}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'sync:%s:%s\n' "$1" "$2" >>"${ACP_TEST_SYNC_LOG}"
mkdir -p "$2/skills/openclaw/agent-control-plane"
printf 'synced\n' >"$2/skills/openclaw/agent-control-plane/SKILL.md"
EOF
chmod +x "${sync_script}"

first_output="$(
  ACP_RUNTIME_SYNC_SCRIPT="${sync_script}" \
  ACP_TEST_SYNC_LOG="${sync_log}" \
  bash "${ENSURE_BIN}" --source-home "${source_home}" --runtime-home "${runtime_home}"
)"
grep -q '^SYNC_STATUS=updated$' <<<"${first_output}"
[[ "$(wc -l <"${sync_log}")" -eq 1 ]]

second_output="$(
  ACP_RUNTIME_SYNC_SCRIPT="${sync_script}" \
  ACP_TEST_SYNC_LOG="${sync_log}" \
  bash "${ENSURE_BIN}" --source-home "${source_home}" --runtime-home "${runtime_home}"
)"
grep -q '^SYNC_STATUS=unchanged$' <<<"${second_output}"
[[ "$(wc -l <"${sync_log}")" -eq 1 ]]

sleep 1
printf 'three\n' >>"${skill_root}/tools/bin/example.sh"

third_output="$(
  ACP_RUNTIME_SYNC_SCRIPT="${sync_script}" \
  ACP_TEST_SYNC_LOG="${sync_log}" \
  bash "${ENSURE_BIN}" --source-home "${source_home}" --runtime-home "${runtime_home}"
)"
grep -q '^SYNC_STATUS=updated$' <<<"${third_output}"
[[ "$(wc -l <"${sync_log}")" -eq 2 ]]
grep -q '^SOURCE_FINGERPRINT=' "${runtime_home}/.agent-control-plane-runtime-sync.env"

default_runtime_home="${tmpdir}/default-runtime-home"
default_output="$(
  ACP_RUNTIME_SYNC_SCRIPT="${sync_script}" \
  ACP_TEST_SYNC_LOG="${sync_log}" \
  bash "${ENSURE_BIN}" --runtime-home "${default_runtime_home}"
)"
grep -q '^SYNC_STATUS=updated$' <<<"${default_output}"
default_runtime_home_real="$(awk -F= '/^RUNTIME_HOME=/{print $2; exit}' <<<"${default_output}")"
grep -q "sync:${FLOW_ROOT}:${default_runtime_home_real}" "${sync_log}"

runtime_skill_root="${tmpdir}/runtime-skill/skills/openclaw/agent-control-plane"
runtime_side_home="${tmpdir}/runtime-side-home"
runtime_side_stamp="${runtime_side_home}/.agent-control-plane-runtime-sync.env"
mkdir -p "${runtime_skill_root}/tools/bin" "${runtime_side_home}"
printf '# runtime skill\n' >"${runtime_skill_root}/SKILL.md"
cat >"${runtime_side_stamp}" <<EOF
SOURCE_HOME='${source_home}'
EOF

runtime_side_output="$(
  ACP_RUNTIME_SYNC_SCRIPT="${sync_script}" \
  ACP_TEST_SYNC_LOG="${sync_log}" \
  AGENT_CONTROL_PLANE_ROOT="${runtime_skill_root}" \
  bash "${ENSURE_BIN}" --runtime-home "${runtime_side_home}"
)"
grep -q '^SYNC_STATUS=updated$' <<<"${runtime_side_output}"
runtime_side_source_home_real="$(awk -F= '/^SOURCE_HOME=/{print $2; exit}' <<<"${runtime_side_output}")"
runtime_side_home_real="$(awk -F= '/^RUNTIME_HOME=/{print $2; exit}' <<<"${runtime_side_output}")"
grep -q "sync:${runtime_side_source_home_real}:${runtime_side_home_real}" "${sync_log}"

skill_root_source_home="${tmpdir}/skill-root-source"
skill_root_runtime_home="${tmpdir}/skill-root-runtime"
mkdir -p "${skill_root_source_home}/tools/bin" "${skill_root_source_home}/assets" "${skill_root_source_home}/bin" "${skill_root_source_home}/hooks"
printf '# test skill\n' >"${skill_root_source_home}/SKILL.md"
printf '{}\n' >"${skill_root_source_home}/assets/workflow-catalog.json"
printf '#!/usr/bin/env bash\n' >"${skill_root_source_home}/bin/agent-control-plane"
printf '#!/usr/bin/env bash\n' >"${skill_root_source_home}/hooks/heartbeat-hooks.sh"
chmod +x "${skill_root_source_home}/bin/agent-control-plane" "${skill_root_source_home}/hooks/heartbeat-hooks.sh"
mkdir -p "${skill_root_source_home}/skills/openclaw/agent-control-plane"
printf '# stale nested skill\n' >"${skill_root_source_home}/skills/openclaw/agent-control-plane/SKILL.md"

skill_root_output="$(
  ACP_RUNTIME_SYNC_SCRIPT="${sync_script}" \
  ACP_TEST_SYNC_LOG="${sync_log}" \
  bash "${ENSURE_BIN}" --source-home "${skill_root_source_home}" --runtime-home "${skill_root_runtime_home}"
)"
grep -q '^SYNC_STATUS=updated$' <<<"${skill_root_output}"
skill_root_source_home_real="$(cd "${skill_root_source_home}" && pwd -P)"
grep -q "^SOURCE_SKILL_DIR=${skill_root_source_home_real}$" <<<"${skill_root_output}"

echo "ensure runtime sync test passed"
