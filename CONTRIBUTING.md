# Contributing to agent-control-plane

Thanks for helping improve `agent-control-plane`.

This project is open to bug fixes, documentation improvements, tests, operator
quality-of-life improvements, and carefully scoped feature work that fits the
runtime and dashboard model already in the repo.

## Before You Open a PR

- open an issue first for large or behavior-changing work
- keep changes focused and easy to review
- add or update tests when behavior changes
- avoid mixing unrelated refactors into the same PR

## Local Validation

At minimum, run the package-facing test before you open a PR:

```bash
npm test
```

For a broader confidence check, run:

```bash
bash tools/bin/test-smoke.sh
```

## Pull Request Expectations

- explain the user-visible or operator-visible change
- mention any runtime or workflow risk
- include verification commands you ran
- update docs if the command surface or behavior changed

## Legal and Licensing

This project is licensed under `MIT`, but contributions are governed by the
Contributor License Agreement in [CLA.md](./CLA.md).

The default contribution model for this repo is:

- you retain copyright in your own contribution
- you confirm that you have the right to submit that contribution
- you grant the maintainer broad rights to use, modify, distribute, sublicense,
  and relicense the contribution as part of this project and derivative works
- standard contributions do not automatically transfer copyright ownership to
  the maintainer

In other words: contributors keep ownership of what they write, but the
maintainer gets a broad enough license to keep the project usable, publishable,
and commercially flexible.

If a contribution would require separate patent, trademark, employment, or
third-party approval, do not submit it until that is cleared. The maintainer
may reject or request a separate written agreement for contributions with
special IP constraints.

## Sponsorship and Contributor Compensation

Repository sponsorships support the project and are managed by the maintainer.

- sponsorships do not create ownership rights in the project
- sponsorships do not automatically create payment obligations to contributors
- contributing code, docs, tests, or ideas does not by itself entitle a person
  to sponsorship payouts
- the maintainer may, at their discretion, use sponsorship funds for
  maintenance, tooling, infrastructure, bounties, or direct contributor support

If the maintainer wants to fund specific contributors, that will be handled as
a separate decision and not as an automatic result of submitting a PR.

## How CLA Acceptance Works

Until an automated CLA bot is wired into this repo, opening a pull request with
an explicit statement that you have read and agree to [CLA.md](./CLA.md) counts
as your acceptance of the CLA for that contribution.

The PR template includes a checkbox for this.
