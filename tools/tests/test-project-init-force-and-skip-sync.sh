#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT_INIT_BIN="${FLOW_ROOT}/tools/bin/project-init.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

call_log="${tmpdir}/calls.log"
source_home="${tmpdir}/source-home"
runtime_home="${tmpdir}/runtime-home"
mkdir -p "${source_home}" "${runtime_home}"

write_stub() {
  local path="${1:?path required}"
  local name="${2:?name required}"
  cat >"${path}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s %s\n' "${name}" "\$*" >>"${call_log}"
EOF
  chmod +x "${path}"
}

scaffold_stub="${tmpdir}/scaffold.sh"
smoke_stub="${tmpdir}/smoke.sh"
adopt_stub="${tmpdir}/adopt.sh"
sync_stub="${tmpdir}/sync.sh"

write_stub "${scaffold_stub}" "scaffold"
write_stub "${smoke_stub}" "smoke"
write_stub "${adopt_stub}" "adopt"
write_stub "${sync_stub}" "sync"

output="$(
  ACP_PROJECT_INIT_SCAFFOLD_SCRIPT="${scaffold_stub}" \
  ACP_PROJECT_INIT_SMOKE_SCRIPT="${smoke_stub}" \
  ACP_PROJECT_INIT_ADOPT_SCRIPT="${adopt_stub}" \
  ACP_PROJECT_INIT_SYNC_SCRIPT="${sync_stub}" \
  ACP_PROJECT_INIT_SOURCE_HOME="${source_home}" \
  ACP_PROJECT_INIT_RUNTIME_HOME="${runtime_home}" \
    bash "${PROJECT_INIT_BIN}" \
      --profile-id demo \
      --repo-slug owner/demo \
      --coding-worker openclaw \
      --force \
      --skip-sync
)"

grep -q 'PROJECT_INIT_STATUS=ok' <<<"${output}"
grep -q 'RUNTIME_SYNC_STATUS=skipped' <<<"${output}"
grep -q 'scaffold --profile-id demo --repo-slug owner/demo --coding-worker openclaw --force' "${call_log}"
grep -q 'smoke --profile-id demo' "${call_log}"
grep -q 'adopt --profile-id demo' "${call_log}"
if grep -q '^sync ' "${call_log}"; then
  echo "expected --skip-sync to avoid sync invocation" >&2
  exit 1
fi

echo "project init force/skip-sync test passed"
