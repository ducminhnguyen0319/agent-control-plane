#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/flow-config-lib.sh"

CONFIG_YAML="$(resolve_flow_config_yaml "${BASH_SOURCE[0]}")"
AGENT_REPO_ROOT="$(flow_resolve_agent_repo_root "${CONFIG_YAML}")"
RETAINED_REPO_ROOT="$(flow_resolve_retained_repo_root "${CONFIG_YAML}")"
VSCODE_WORKSPACE_FILE="$(flow_resolve_vscode_workspace_file "${CONFIG_YAML}")"
DEFAULT_BRANCH="$(flow_resolve_default_branch "${CONFIG_YAML}")"
PROJECT_LABEL="$(flow_resolve_project_label "${CONFIG_YAML}")"

mkdir -p "$(dirname "$VSCODE_WORKSPACE_FILE")"

AGENT_REPO_ROOT="$AGENT_REPO_ROOT" \
RETAINED_REPO_ROOT="$RETAINED_REPO_ROOT" \
VSCODE_WORKSPACE_FILE="$VSCODE_WORKSPACE_FILE" \
DEFAULT_BRANCH="$DEFAULT_BRANCH" \
PROJECT_LABEL="$PROJECT_LABEL" \
node <<'EOF'
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const agentRepoRoot = process.env.AGENT_REPO_ROOT;
const retainedRepoRoot = process.env.RETAINED_REPO_ROOT;
const workspaceFile = process.env.VSCODE_WORKSPACE_FILE;
const defaultBranch = process.env.DEFAULT_BRANCH || 'main';
const projectLabel = process.env.PROJECT_LABEL || 'project';

if (!workspaceFile) {
  throw new Error('VSCODE_WORKSPACE_FILE is required');
}

function parseWorktrees(raw) {
  const entries = [];
  let current = null;

  for (const line of raw.split('\n')) {
    if (line.length === 0) {
      if (current?.path) {
        entries.push(current);
      }
      current = null;
      continue;
    }

    if (line.startsWith('worktree ')) {
      if (current?.path) {
        entries.push(current);
      }
      current = { path: line.slice('worktree '.length) };
      continue;
    }

    if (!current) {
      continue;
    }

    if (line.startsWith('branch ')) {
      current.branch = line.slice('branch '.length).replace(/^refs\/heads\//, '');
      continue;
    }
  }

  if (current?.path) {
    entries.push(current);
  }

  return entries;
}

function titleCase(value) {
  if (!value) return '';
  return value.charAt(0).toUpperCase() + value.slice(1);
}

function folderNameFor(entry) {
  const branch = entry.branch || '';
  const base = path.basename(entry.path);

  if (branch === defaultBranch) {
    return `${projectLabel} (Automation ${titleCase(defaultBranch)})`;
  }

  const prMatch = branch.match(/(?:^|\/)pr-(\d+)/);
  if (prMatch) {
    return `PR ${prMatch[1]} (${base})`;
  }

  const issueMatch = branch.match(/issue-(\d+)/);
  if (issueMatch) {
    return `Issue ${issueMatch[1]} (${base})`;
  }

  return branch ? `${branch} (${base})` : base;
}

const retainedResolved = retainedRepoRoot ? path.resolve(retainedRepoRoot) : '';
const folders = [];
const seen = new Set();
const agentResolved = agentRepoRoot ? path.resolve(agentRepoRoot) : '';
const agentIsGit =
  !!agentRepoRoot && (
    fs.existsSync(path.join(agentRepoRoot, '.git'))
    || fs.existsSync(`${agentRepoRoot}.git`)
    || fs.existsSync(path.join(agentRepoRoot, '.git', 'HEAD'))
  );

if (retainedResolved && fs.existsSync(retainedResolved)) {
  folders.push({
    name: `${projectLabel} (Main)`,
    path: retainedResolved,
  });
  seen.add(retainedResolved);
}

if (agentResolved && fs.existsSync(agentResolved) && !seen.has(agentResolved)) {
  folders.push({
    name: `${projectLabel} (Automation ${titleCase(defaultBranch)})`,
    path: agentResolved,
  });
  seen.add(agentResolved);
}

if (agentIsGit) {
  const raw = execFileSync('git', ['-C', agentRepoRoot, 'worktree', 'list', '--porcelain'], {
    encoding: 'utf8',
  });

  for (const entry of parseWorktrees(raw)) {
    const resolved = path.resolve(entry.path);
    if (resolved === agentResolved) {
      continue;
    }
    if (!fs.existsSync(resolved) || seen.has(resolved)) {
      continue;
    }
    folders.push({
      name: folderNameFor(entry),
      path: resolved,
    });
    seen.add(resolved);
  }
}

const workspace = {
  folders,
  settings: {
    'git.autoRepositoryDetection': 'subFolders',
  },
};

fs.writeFileSync(workspaceFile, `${JSON.stringify(workspace, null, 2)}\n`, 'utf8');
EOF
