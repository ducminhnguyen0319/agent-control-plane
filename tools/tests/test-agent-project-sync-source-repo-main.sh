#!/usr/bin/env bash
set -euo pipefail

FLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_SCRIPT="${FLOW_ROOT}/tools/bin/agent-project-sync-source-repo-main"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

remote_repo="$tmpdir/remote.git"
seed_repo="$tmpdir/seed"
source_repo="$tmpdir/source"
state_root="$tmpdir/state"
config_file="$tmpdir/control-plane.yaml"

git init --bare "$remote_repo" >/dev/null 2>&1
git init "$seed_repo" >/dev/null 2>&1
git -C "$seed_repo" config user.name "ACP Test"
git -C "$seed_repo" config user.email "acp@example.com"
cat >"$seed_repo/README.md" <<'EOF'
seed
EOF
git -C "$seed_repo" add README.md
git -C "$seed_repo" commit -m "seed" >/dev/null 2>&1
git -C "$seed_repo" branch -M main
git -C "$seed_repo" remote add origin "$remote_repo"
git -C "$seed_repo" push -u origin main >/dev/null 2>&1

git clone "$remote_repo" "$source_repo" >/dev/null 2>&1
git -C "$source_repo" remote add gitea "$remote_repo"
git -C "$source_repo" checkout -B main origin/main >/dev/null 2>&1
git -C "$source_repo" checkout -b feature/local >/dev/null 2>&1
before_main_sha="$(git -C "$source_repo" rev-parse refs/heads/main)"

cat >"$seed_repo/README.md" <<'EOF'
seed
next
EOF
git -C "$seed_repo" add README.md
git -C "$seed_repo" commit -m "next" >/dev/null 2>&1
git -C "$seed_repo" push origin main >/dev/null 2>&1
remote_main_sha="$(git -C "$seed_repo" rev-parse HEAD)"

cat >"$config_file" <<EOF
schema_version: "1"
id: "demo"
repo:
  slug: "acp-admin/agent-control-plane"
  root: "${tmpdir}/canonical"
  default_branch: "main"
runtime:
  state_root: "${state_root}"
  retained_repo_root: "${tmpdir}/retained"
  source_repo_root: "${source_repo}"
EOF

output="$(
  ACP_FORGE_PROVIDER="gitea" \
  ACP_SOURCE_SYNC_REMOTE="gitea" \
  ACP_SOURCE_REPO_SYNC_CONFIG_YAML="$config_file" \
    bash "$SOURCE_SCRIPT"
)"

grep -q '^SOURCE_REPO_SYNC_STATUS=updated$' <<<"$output"
grep -q "^SOURCE_REPO_ROOT=${source_repo}$" <<<"$output"
grep -q "^REMOTE_NAME=gitea$" <<<"$output"
grep -q "^SOURCE_REPO_SYNC_SHA=${remote_main_sha}$" <<<"$output"

after_main_sha="$(git -C "$source_repo" rev-parse refs/heads/main)"
current_branch="$(git -C "$source_repo" branch --show-current)"

[[ "$before_main_sha" != "$remote_main_sha" ]]
[[ "$after_main_sha" == "$remote_main_sha" ]]
[[ "$current_branch" == "feature/local" ]]

grep -q '^STATUS=updated$' "$state_root/source-repo-main-sync.env"
grep -q '^DETAIL=fast-forward-local-ref$' "$state_root/source-repo-main-sync.env"

git -C "$source_repo" checkout main >/dev/null 2>&1
git -C "$source_repo" config user.name "ACP Test"
git -C "$source_repo" config user.email "acp@example.com"
cat >"$source_repo/local.txt" <<'EOF'
local
EOF
git -C "$source_repo" add local.txt
git -C "$source_repo" commit -m "local-main-work" >/dev/null 2>&1
local_main_before_merge_sha="$(git -C "$source_repo" rev-parse HEAD)"

cat >"$seed_repo/remote.txt" <<'EOF'
remote
EOF
git -C "$seed_repo" add remote.txt
git -C "$seed_repo" commit -m "remote-main-work" >/dev/null 2>&1
git -C "$seed_repo" push origin main >/dev/null 2>&1
remote_main_merge_sha="$(git -C "$seed_repo" rev-parse HEAD)"

merge_output="$(
  ACP_FORGE_PROVIDER="gitea" \
  ACP_SOURCE_SYNC_REMOTE="gitea" \
  ACP_SOURCE_REPO_SYNC_CONFIG_YAML="$config_file" \
    bash "$SOURCE_SCRIPT"
)"

grep -q '^SOURCE_REPO_SYNC_STATUS=updated$' <<<"$merge_output"
grep -q '^STATUS=updated$' "$state_root/source-repo-main-sync.env"
grep -q '^DETAIL=merge-checked-out-branch$' "$state_root/source-repo-main-sync.env"

merged_head_sha="$(git -C "$source_repo" rev-parse HEAD)"
git -C "$source_repo" merge-base --is-ancestor "$local_main_before_merge_sha" "$merged_head_sha"
git -C "$source_repo" merge-base --is-ancestor "$remote_main_merge_sha" "$merged_head_sha"

echo "agent-project-sync-source-repo-main test passed"
