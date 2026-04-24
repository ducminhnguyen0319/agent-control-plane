#!/usr/bin/env bash
set -euo pipefail

# Test systemd scripts syntax and basic structure

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bin_dir="$(cd "${script_dir}/../bin" && pwd)"
errors=0

echo "=== Testing systemd scripts ==="

# Check files exist
for script in install-project-systemd.sh project-systemd-bootstrap.sh uninstall-project-systemd.sh; do
  if [[ ! -f "${bin_dir}/${script}" ]]; then
    echo "FAIL: ${script} not found in ${bin_dir}"
    ((errors+=1))
  else
    echo "PASS: ${script} exists"
  fi
done

# Check executable
for script in install-project-systemd.sh project-systemd-bootstrap.sh uninstall-project-systemd.sh; do
  if [[ -f "${bin_dir}/${script}" && ! -x "${bin_dir}/${script}" ]]; then
    echo "FAIL: ${script} not executable"
    ((errors+=1))
  elif [[ -f "${bin_dir}/${script}" ]]; then
    echo "PASS: ${script} is executable"
  fi
done

# Syntax check
for script in install-project-systemd.sh project-systemd-bootstrap.sh uninstall-project-systemd.sh; do
  if [[ -f "${bin_dir}/${script}" ]]; then
    if bash -n "${bin_dir}/${script}" 2>/dev/null; then
      echo "PASS: ${script} syntax OK"
    else
      echo "FAIL: ${script} syntax error"
      ((errors+=1))
    fi
  fi
done

# Check project-runtimectl.sh has systemd functions
runtimectl="${bin_dir}/project-runtimectl.sh"
if [[ -f "${runtimectl}" ]]; then
  for func in systemd_service_enabled_for_profile systemd_service_state; do
    if grep -q "${func}()" "${runtimectl}"; then
      echo "PASS: ${func} found in project-runtimectl.sh"
    else
      echo "FAIL: ${func} not found in project-runtimectl.sh"
      ((errors+=1))
    fi
  done
  
  for var in SYSTEMCTL_BIN SYSTEMD_DIR SYSTEMD_UNIT_NAME; do
    if grep -q "${var}" "${runtimectl}"; then
      echo "PASS: ${var} found in project-runtimectl.sh"
    else
      echo "FAIL: ${var} not found in project-runtimectl.sh"
      ((errors+=1))
    fi
  done
else
  echo "FAIL: project-runtimectl.sh not found"
  ((errors+=1))
fi

echo ""
if [[ "${errors}" -eq 0 ]]; then
  echo "=== ALL TESTS PASSED ==="
  exit 0
else
  echo "=== ${errors} TEST(S) FAILED ==="
  exit 1
fi
