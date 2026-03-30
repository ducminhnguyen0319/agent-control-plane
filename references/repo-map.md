# Repository Map

This file maps the `agent-control-plane` repository itself.

## Core Layout

- `SKILL.md`
  Shared operating manual for the control plane.
- `assets/`
  Workflow catalog and static non-profile assets.
- `bin/`
  Queue, label, and risk scripts shared by installed profiles.
- `hooks/`
  Heartbeat and reconcile hooks shared by installed profiles.
- `tools/bin/`
  Runtime wrappers, onboarding helpers, publication utilities, and doctor tools.
- `tools/templates/`
  Generic fallback prompts used when a profile does not override a template.
- `tools/tests/`
  Shell regression coverage for control-plane behavior.
- `references/`
  Control-plane docs, operator commands, and repository maps.

## Operator Surfaces

- `tools/bin/render-flow-config.sh`
  Effective config viewer for the selected profile.
- `tools/bin/profile-smoke.sh`
  Installed-profile validation and collision detection.
- `tools/bin/profile-adopt.sh`
  Local runtime/bootstrap helper for onboarding a profile onto a workstation.
- `tools/bin/sync-shared-agent-home.sh`
  Publication repair for shared/runtime copies.

Installed profiles live outside this repo under
`~/.agent-runtime/control-plane/profiles/<id>/`.
