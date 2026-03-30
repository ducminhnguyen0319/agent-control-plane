# Release Checklist

Maintainer checklist for shipping a new public package release of
`agent-control-plane`.

## Pre-Release

- confirm `git status` is clean
- confirm `package.json` version is intentional
- review `CHANGELOG.md` and prepare release notes from
  `.github/release-template.md`
- refresh README demo media if the dashboard UI changed:
  `bash tools/bin/render-dashboard-demo-media.sh`
- review `README.md`, `SECURITY.md`, `CONTRIBUTING.md`, and `CLA.md` for stale
  links or policy text
- if a public GitHub repo now exists, set or verify the `homepage`,
  `repository`, and `bugs` URLs in `package.json`
- make sure sponsor links still point to the intended maintainer identity
- confirm the intended license is still `MIT`

## Verification

Run the core checks:

```bash
bash tools/tests/test-package-public-metadata.sh
bash tools/tests/test-package-funding-metadata.sh
bash tools/tests/test-contribution-docs.sh
bash tools/tests/test-agent-control-plane-npm-cli.sh
bash tools/bin/test-smoke.sh
npm pack --dry-run
```

## Publish

Recommended release flow uses npm trusted publishing from GitHub Actions, so you
do not have to enter an OTP during every local publish.

One-time setup:

- configure `agent-control-plane` for npm trusted publishing from
  `ducminhnguyen0319/agent-control-plane`
- verify the publish workflow file is `.github/workflows/publish.yml`
- keep npm package publishing policy on the stricter setting you want after
  trusted publishing is working

Per-release command flow:

```bash
npm version <patch|minor|major>
git push origin main --follow-tags
```

Then:

- watch `.github/workflows/publish.yml` for the npm publish run
- create or update a GitHub release using `.github/release-template.md`
- update `CHANGELOG.md` if the final shipped notes differ from the draft

## Post-Release

- verify `npx agent-control-plane@latest help` works from a clean shell
- verify the npm package shows provenance for the new version
- verify `npm fund` shows the expected sponsor link
- verify the repo README, sponsor button, and package metadata all point to the
  same maintainer identity
- announce the release where relevant
