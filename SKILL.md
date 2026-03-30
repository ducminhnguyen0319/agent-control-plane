---
name: agent-control-plane
description: Use when working on the shared multi-project agent control plane, including scheduler/runtime orchestration, worktree and worker lifecycle, profile onboarding, and cross-project automation flows.
---

# Agent Control Plane

This repository is the canonical `agent-control-plane` package. It owns the
generic scheduler/runtime, worktree lifecycle, profile onboarding, queue/risk
automation, and profile-scoped prompt/template resolution used across multiple
projects.

Installed project profiles live under
`~/.agent-runtime/control-plane/profiles/<id>/`. Treat the control plane itself
as generic, then load the selected profile's local guidance only when the task
is truly about that project. Integrated project data should stay in that
external profile registry, not inside this repository.

## What Lives Here

- core operating manual in this `SKILL.md`
- installed project profiles in `~/.agent-runtime/control-plane/profiles/*/control-plane.yaml`
- installed profile notes in `~/.agent-runtime/control-plane/profiles/*/README.md`
- workflow catalog in `assets/workflow-catalog.json`
- worker dashboard in `tools/dashboard/` with launchers in `tools/bin/render-dashboard-snapshot.py`
  and `tools/bin/serve-dashboard.sh`
- dashboard autostart helpers in `tools/bin/dashboard-launchd-bootstrap.sh` and
  `tools/bin/install-dashboard-launchd.sh`
- project autostart helpers in `tools/bin/project-launchd-bootstrap.sh`,
  `tools/bin/install-project-launchd.sh`, and
  `tools/bin/uninstall-project-launchd.sh`
- queue/label/risk scripts in `bin/`
- heartbeat and reconcile hooks in `hooks/`
- shared runtime wrappers, onboarding tools, and tests in `tools/bin/` and
  `tools/tests/`

The vendored runtime entrypoints used by live schedulers are published from this
checkout into the shared canonical skill copy under
`skills/openclaw/agent-control-plane`, then copied into
`~/.agent-runtime/runtime-home/skills/openclaw/agent-control-plane` by
`tools/bin/sync-shared-agent-home.sh`.

## Required Startup Sequence

Before doing non-trivial work in this repository or on an integrated project:

1. Determine the active profile with `AGENT_PROJECT_ID`, `ACP_PROJECT_ID`, or
   `tools/bin/render-flow-config.sh`.
2. Read the selected profile notes in
   `~/.agent-runtime/control-plane/profiles/<id>/README.md` when they exist.
3. Read the selected repo's local startup docs before changing behavior:
   `AGENTS.md`, `openspec/AGENT_RULES.md`, `openspec/AGENTS.md`,
   `openspec/project.md`, and `openspec/CONVENTIONS.md`.
4. Use a clean read-only inspection checkout first; move to an isolated
   worktree or agent-owned checkout before making non-trivial edits.
5. If the task changes product behavior, inspect the active OpenSpec changes
   before implementation.

For onboarding a new repository onto the shared control plane:

1. Prefer `tools/bin/project-init.sh --profile-id <id> --repo-slug <owner/repo>`
2. Fill in `~/.agent-runtime/control-plane/profiles/<id>/README.md`
3. If you need manual control, the underlying steps remain:
   `tools/bin/scaffold-profile.sh`, `tools/bin/profile-smoke.sh`,
   `tools/bin/profile-adopt.sh`, and `tools/bin/sync-shared-agent-home.sh`

For runtime control of one installed profile:

1. Check state with `tools/bin/project-runtimectl.sh status --profile-id <id>`
2. Start or ensure runtime with `tools/bin/project-runtimectl.sh start --profile-id <id>`
3. Stop or recycle runtime with `tools/bin/project-runtimectl.sh stop --profile-id <id>`
4. Use `tools/bin/project-runtimectl.sh restart --profile-id <id>` for a clean bounce
5. Use `tools/bin/install-project-launchd.sh --profile-id <id>` when one
   profile should survive reboot/login via a per-project LaunchAgent
6. Remove per-project autostart with
   `tools/bin/uninstall-project-launchd.sh --profile-id <id>`
7. Remove an installed profile with `tools/bin/project-remove.sh --profile-id <id>`

## Task Routing

Pick the smallest matching path and load only the relevant references:

- Control-plane layout, publication model, and profile ownership:
  `references/control-plane-map.md`
- Control-plane operator commands and profile-management entrypoints:
  `references/commands.md`
- Control-plane repository layout:
  `references/repo-map.md`
- Control-plane docs and profile guidance locations:
  `references/docs-map.md`
- Project-specific rules and repo commands:
  `~/.agent-runtime/control-plane/profiles/<id>/README.md`

## Repo Rules That Matter Most

- Keep the core engine generic. Put repo-specific behavior behind a profile,
  profile templates, or profile-scoped docs instead of hardcoding it into the
  shared runtime.
- Follow OpenSpec and the selected repo's local rules before implementing
  product behavior changes.
- Do not simplify or change approach without explicit user approval.
- Prefer deterministic wrappers and config-driven routing over special-case
  conditionals.
- For any non-trivial write task, use a dedicated agent worktree or another
  isolated clean checkout.
- Preserve dirty retained checkouts; continue from a fresh isolated worktree
  instead of layering more edits there.
- Prefer canonical docs and profile-local notes over stale audits or incidental
  markdown snapshots.
- When updating the control plane itself, repair published copies after the
  source change so runtime and source do not drift.

## Common Operating Patterns

### Analysis and Planning

- Resolve the active profile first.
- Read `~/.agent-runtime/control-plane/profiles/<id>/README.md` for repo-local context.
- Use `references/docs-map.md` to find the canonical control-plane or
  profile-local source instead of scanning random files.

### Implementation

- Keep generic scheduler/runtime changes in the shared engine.
- Put repo-specific prompts, commands, or heuristics in the installed profile
  directory under `~/.agent-runtime/control-plane/profiles/<id>/`.
- Keep changes reversible and tightly scoped.

### Testing

- Use `references/commands.md` for control-plane checks.
- Use the selected profile's README for repo-specific dev/test commands.
- Re-run `tools/bin/profile-smoke.sh`, `tools/bin/check-skill-contracts.sh`,
  dashboard tests, and targeted shell tests after meaningful control-plane
  changes.

### Publishing and Runtime Health

- Use `tools/bin/flow-runtime-doctor.sh` to confirm source/runtime sync.
- Use `tools/bin/sync-shared-agent-home.sh` after changing runtime-facing files.
- Prefer copied published artifacts over symlink aliases.

## References

- `references/control-plane-map.md`
- `references/commands.md`
- `references/repo-map.md`
- `references/docs-map.md`
- `~/.agent-runtime/control-plane/profiles/<id>/README.md`
