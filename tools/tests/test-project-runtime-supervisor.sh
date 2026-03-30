#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUPERVISOR_BIN="${FLOW_ROOT}/tools/bin/project-runtime-supervisor.sh"

tmpdir="$(mktemp -d)"
supervisor_pid=""
cleanup() {
  if [[ -n "${supervisor_pid}" ]]; then
    kill "${supervisor_pid}" >/dev/null 2>&1 || true
    wait "${supervisor_pid}" >/dev/null 2>&1 || true
  fi
  rm -rf "${tmpdir}"
}
trap cleanup EXIT

pid_file="${tmpdir}/runtime-supervisor.pid"
bootstrap_log="${tmpdir}/bootstrap.log"
bootstrap_script="${tmpdir}/bootstrap.sh"

cat >"${bootstrap_script}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'bootstrap %s\n' "\$(date +%s)" >>"${bootstrap_log}"
EOF
chmod +x "${bootstrap_script}"

bash "${SUPERVISOR_BIN}" \
  --bootstrap-script "${bootstrap_script}" \
  --pid-file "${pid_file}" \
  --interval-seconds 1 >/dev/null 2>&1 &
supervisor_pid="$!"

for _ in 1 2 3 4 5; do
  if [[ -f "${pid_file}" ]] && [[ -f "${bootstrap_log}" ]] && [[ "$(wc -l <"${bootstrap_log}" | tr -d ' ')" -ge 2 ]]; then
    break
  fi
  sleep 1
done

test -f "${pid_file}"
test "$(cat "${pid_file}")" = "${supervisor_pid}"
test "$(wc -l <"${bootstrap_log}" | tr -d ' ')" -ge 2
kill -0 "${supervisor_pid}" 2>/dev/null

echo "project runtime supervisor test passed"
