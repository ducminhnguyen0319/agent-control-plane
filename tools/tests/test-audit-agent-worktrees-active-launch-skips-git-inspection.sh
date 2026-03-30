#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AUDIT_SCRIPT="${FLOW_ROOT}/tools/bin/audit-agent-worktrees.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

repo_root="$tmpdir/repo"
worktree_root="$tmpdir/worktrees"
agent_root="$tmpdir/agent"
shim_dir="$tmpdir/shim"

mkdir -p "$repo_root" "$worktree_root" "$agent_root/runs" "$agent_root/state/pending-launches" "$shim_dir"
repo_root="$(cd "$repo_root" && pwd -P)"
worktree_root="$(cd "$worktree_root" && pwd -P)"
agent_root="$(cd "$agent_root" && pwd -P)"
shim_dir="$(cd "$shim_dir" && pwd -P)"

git -C "$repo_root" init -b main >/dev/null 2>&1
git -C "$repo_root" config user.name "Codex"
git -C "$repo_root" config user.email "codex@example.com"
printf 'root\n' >"$repo_root/README.md"
git -C "$repo_root" add README.md
git -C "$repo_root" commit -m "init" >/dev/null 2>&1

worktree_path="$worktree_root/issue-360-active-launch-skip"
git -C "$repo_root" worktree add -b "agent/alpha/issue-360-active-launch-skip" "$worktree_path" main >/dev/null 2>&1
worktree_path="$(cd "$worktree_path" && pwd -P)"

sleep 60 &
pending_pid=$!
printf '%s\n' "$pending_pid" >"$agent_root/state/pending-launches/issue-360.pid"

cat >"$shim_dir/git" <<EOF
#!/usr/bin/env bash
set -euo pipefail
real_git="$(command -v git)"
protected_worktree="${worktree_path}"

if [[ "\${1:-}" == "-C" && "\${2:-}" == "\$protected_worktree" ]]; then
  case "\${3:-}" in
    rev-parse|status)
      echo "unexpected git inspection for active-launch worktree" >&2
      exit 99
      ;;
  esac
fi

exec "\$real_git" "\$@"
EOF
chmod +x "$shim_dir/git"

output="$(
  PATH="$shim_dir:$PATH" \
  F_LOSNING_AGENT_REPO_ROOT="$repo_root" \
  F_LOSNING_WORKTREE_ROOT="$worktree_root" \
  F_LOSNING_AGENT_ROOT="$agent_root" \
  bash "$AUDIT_SCRIPT" --cleanup
)"

kill "$pending_pid" >/dev/null 2>&1 || true
wait "$pending_pid" 2>/dev/null || true

grep -q '^LEGACY_AGENT_WORKTREE_COUNT=0$' <<<"$output"
test -d "$worktree_path"

echo "audit agent worktrees active-launch inspection skip test passed"
