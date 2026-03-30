# Docs Map

Canonical documentation sources inside `agent-control-plane`:

## Shared Control-Plane Docs

- `SKILL.md`
  Shared operating rules and startup sequence.
- `README.md`
  Public-facing install, usage, funding, contributing, and security entrypoint.
- `CHANGELOG.md`
  Public release history for the package and repository.
- `ROADMAP.md`
  Public product and backend-support roadmap, including current and planned
  worker integrations.
- `references/architecture.md`
  Architecture walkthrough with system, runtime, worker, and dashboard diagrams.
- `CONTRIBUTING.md`
  Contributor workflow, legal model, and maintainer expectations.
- `CLA.md`
  Contributor license agreement used for incoming changes.
- `CODE_OF_CONDUCT.md`
  Community behavior and moderation expectations.
- `SECURITY.md`
  Security reporting path and disclosure expectations.
- `references/control-plane-map.md`
  Ownership map for profiles, scripts, publication copies, and operator tools.
- `references/commands.md`
  Control-plane operator commands and profile-management entrypoints.
- `references/release-checklist.md`
  Maintainer release checklist for public package publishing.
- `.github/release-template.md`
  Reusable markdown template for GitHub release notes.
- `.github/workflows/ci.yml`
  Public CI workflow used for the README status badge.
- `.github/workflows/publish.yml`
  Trusted npm publishing workflow used for tag-driven releases with provenance.
- `references/repo-map.md`
  Layout of the control-plane repository itself.

## Profile-Scoped Docs

- `~/.agent-runtime/control-plane/profiles/<id>/README.md`
  Canonical repo-specific startup docs, repo roots, command map, and
  high-risk notes.
- `~/.agent-runtime/control-plane/profiles/<id>/control-plane.yaml`
  Canonical machine-readable installed profile config.
- `~/.agent-runtime/control-plane/profiles/<id>/templates/*.md`
  Canonical prompt overrides for issue, PR fix, PR review, or scheduled issue flows.

## Runtime and Publication Docs

- `tools/bin/flow-runtime-doctor.sh`
  Sync health for source and runtime copies.
- `tools/bin/profile-smoke.sh`
  Installed-profile validation before scheduler use.
- `tools/bin/profile-adopt.sh`
  Local workstation adoption helper.
- `tools/bin/sync-shared-agent-home.sh`
  Publication repair for shared/runtime copies.
- `tools/bin/render-dashboard-demo-media.sh`
  Regenerates the README dashboard screenshot and animated walkthrough from a
  real local demo fixture.
- `tools/bin/render-architecture-infographics.sh`
  Regenerates the architecture infographic PNGs and PDF deck from the local
  HTML source in `tools/architecture/`.

## Rule of Thumb

If a piece of guidance is specific to one repo, keep it in
`~/.agent-runtime/control-plane/profiles/<id>/README.md` or
`~/.agent-runtime/control-plane/profiles/<id>/templates/` instead of the shared
control-plane docs.
