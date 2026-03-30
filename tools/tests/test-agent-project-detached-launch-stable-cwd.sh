#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLOW_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CLI_SCRIPT="${FLOW_ROOT}/npm/bin/agent-control-plane.js"
DETACHED_LAUNCH_SCRIPT="${FLOW_ROOT}/tools/bin/agent-project-detached-launch"

realpath_safe() {
  python3 - "$1" <<'PY'
import os
import sys
print(os.path.realpath(sys.argv[1]))
PY
}

tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "${tmpdir}"
}
trap cleanup EXIT

platform_home="${tmpdir}/platform"
home_dir="${tmpdir}/home"
mkdir -p "${platform_home}" "${home_dir}"

HOME="${home_dir}" \
AGENT_PLATFORM_HOME="${platform_home}" \
ACP_PROFILE_REGISTRY_ROOT="${platform_home}/control-plane/profiles" \
node "${CLI_SCRIPT}" sync >/dev/null

HOME="${home_dir}" \
AGENT_PLATFORM_HOME="${platform_home}" \
ACP_PROFILE_REGISTRY_ROOT="${platform_home}/control-plane/profiles" \
node "${CLI_SCRIPT}" init \
  --profile-id detached-launch \
  --repo-slug example-owner/detached-launch \
  --allow-missing-repo \
  --skip-anchor-sync \
  --skip-workspace-sync >/dev/null

config_yaml="${platform_home}/control-plane/profiles/detached-launch/control-plane.yaml"
test -f "${config_yaml}"

expected_cwd="${platform_home}/projects/detached-launch/repo"
mkdir -p "${expected_cwd}"

writer_script="${tmpdir}/write-pwd.sh"
cat >"${writer_script}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
pwd >"$1"
EOF
chmod +x "${writer_script}"

output_file="${tmpdir}/child-pwd.txt"
foreign_cwd="${tmpdir}/foreign-cwd"
mkdir -p "${foreign_cwd}"

launch_output="$(
  (
    cd "${foreign_cwd}"
    HOME="${home_dir}" \
    AGENT_PLATFORM_HOME="${platform_home}" \
    ACP_PROFILE_REGISTRY_ROOT="${platform_home}/control-plane/profiles" \
    AGENT_CONTROL_PLANE_CONFIG="${config_yaml}" \
    ACP_PROJECT_ID=detached-launch \
    "${DETACHED_LAUNCH_SCRIPT}" detached-launch-test "${writer_script}" "${output_file}"
  )
)"

grep -q '^LAUNCH_MODE=detached$' <<<"${launch_output}"
launch_cwd="$(awk -F= '/^LAUNCH_CWD=/{print $2; exit}' <<<"${launch_output}")"
[[ -n "${launch_cwd}" ]]
[[ "$(realpath_safe "${launch_cwd}")" != "$(realpath_safe "${foreign_cwd}")" ]]

for _ in $(seq 1 50); do
  if [[ -f "${output_file}" ]]; then
    break
  fi
  sleep 0.1
done

test -f "${output_file}"
child_cwd="$(cat "${output_file}")"
[[ "$(realpath_safe "${child_cwd}")" == "$(realpath_safe "${launch_cwd}")" ]]

echo "detached launch stable cwd test passed"
