#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REAL_CONFIG_LIB="${FLOW_ROOT}/tools/bin/flow-config-lib.sh"
REAL_SHELL_LIB="${FLOW_ROOT}/tools/bin/flow-shell-lib.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

bin_dir="$tmpdir/bin"
mkdir -p "$bin_dir"

cp "$REAL_CONFIG_LIB" "$bin_dir/flow-config-lib.sh"
cp "$REAL_SHELL_LIB" "$bin_dir/flow-shell-lib.sh"

cat >"$bin_dir/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "auth" && "${2:-}" == "status" ]]; then
  if [[ -n "${GH_TOKEN:-}" ]]; then
    echo "unexpected GH_TOKEN during auth status" >&2
    exit 1
  fi
  exit 0
fi

if [[ "${1:-}" == "api" && "${2:-}" == "user" ]]; then
  if [[ -n "${GH_TOKEN:-}" ]]; then
    echo "unexpected GH_TOKEN during gh api user" >&2
    exit 1
  fi
  if [[ "${3:-}" == "--jq" ]]; then
    printf 'demo-user\n'
  else
    printf '{"login":"demo-user"}\n'
  fi
  exit 0
fi

echo "unexpected gh invocation: $*" >&2
exit 1
EOF
chmod +x "$bin_dir/gh"

cat >"$bin_dir/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "credential" && "${2:-}" == "fill" ]]; then
  cat <<'PAYLOAD'
protocol=https
host=github.com
username=demo
password=git-credential-token
PAYLOAD
  exit 0
fi

echo "unexpected git invocation: $*" >&2
exit 1
EOF
chmod +x "$bin_dir/git"

output="$(
  LIB_PATH="$bin_dir/flow-config-lib.sh" \
  PATH="$bin_dir:/usr/bin:/bin:/usr/sbin:/sbin" \
  bash <<'EOF'
set -euo pipefail
source "$LIB_PATH"
unset GH_TOKEN
unset GITHUB_TOKEN
flow_export_github_cli_auth_env "example/demo"
printf 'GH_TOKEN=%s\n' "${GH_TOKEN:-}"
EOF
)"

test "$output" = "GH_TOKEN="

echo "flow github auth prefers gh session over git credential test passed"
