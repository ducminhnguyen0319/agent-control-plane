# Task

Implement issue #{ISSUE_ID} in `{REPO_SLUG}`.

# Issue Context

- Title: {ISSUE_TITLE}
- URL: {ISSUE_URL}
- Auto-merge requested: {ISSUE_AUTOMERGE}

{ISSUE_BODY}
{ISSUE_RECURRING_CONTEXT}
{ISSUE_BLOCKER_CONTEXT}

# MANDATORY WORKFLOW (follow in order, no skipping)

You MUST complete ALL 5 phases in order. Do not skip any phase. Do not commit until Phase 4 passes.

## Phase 1: READ & SCOPE

- Read the repo instructions: `AGENTS.md`, relevant spec or design docs, and any repo conventions tied to this issue.
- Identify the single primary product surface you will touch.
- If the issue spans multiple surfaces, pick ONE and create follow-up issues for the rest using:
  ```bash
  bash "$ACP_FLOW_TOOLS_DIR/create-follow-up-issue.sh" --parent {ISSUE_ID} --title "..." --body-file /tmp/follow-up.md
  ```
- Treat a broad umbrella issue as a coordination brief rather than permission to ship every slice in one PR.
- Write down your scope decision before coding.

## Phase 2: IMPLEMENT

- Make the smallest root-cause fix that satisfies the issue.
- Work only inside the dedicated worktree.
- Add or update tests when feasible.
- STOP after implementation. Do not commit yet.

## Phase 3: VERIFY (MANDATORY)

After implementing, you MUST run verification commands and record each one.
Every successful command must be recorded or the host publish will fail.
After each successful verification command, record it with `record-verification.sh`.

```bash
{ISSUE_VERIFICATION_COMMAND_SNIPPET}
```

Required verification coverage:
- Run the narrowest repo-supported `typecheck`, `build`, `test`, or `lint` command that proves the touched surface is safe.
- If you changed tests only, run the most relevant targeted test command and record it.
- If you changed localization resources or user-facing copy, run repo locale validation or hardcoded-copy scans if the repo provides them.
- If a verification command fails, fix the issue and rerun until it passes.

CRITICAL: `verification.jsonl` must exist in `$ACP_RUN_DIR` with at least one `pass` entry before you can write `OUTCOME=implemented`.

## Phase 4: SELF-REVIEW (MANDATORY)

Before committing, perform this checklist:

- [ ] Run `git diff --check`.
- [ ] Count non-test product files: if the change is broad, stop and split scope instead of publishing one large PR.
- [ ] If you touched auth, login, session, or reset flows, verify existing users and legacy data still behave correctly.
- [ ] If you touched public endpoints, public routes, or operator workflows, search downstream consumers in `scripts/`, `docs/`, and specs.
- [ ] If you changed localization resources or user-facing copy, confirm localization coverage and scanning are still valid.
- [ ] If you touched mobile routes or screens, keep route scope narrow and verify loading, empty, and error states.

Before committing, verify the journal exists:
```bash
test -s "$ACP_RUN_DIR/verification.jsonl" && echo "OK: verification.jsonl exists" || echo "BLOCKED: missing verification.jsonl"
```

## Phase 5: COMMIT & REPORT

- Commit with a conventional commit message.
- Do NOT push or open a PR; the host handles that.
- Write `$ACP_RESULT_FILE`:
  ```bash
  cat > "$ACP_RESULT_FILE" <<'OUTER_EOF'
  OUTCOME=implemented
  ACTION=host-publish-issue-pr
  ISSUE_ID={ISSUE_ID}
  OUTER_EOF
  ```
- In your final output, include the changed files, verification commands actually run, and one short self-review note naming the main regression risk you checked.

# STOP CONDITIONS

Stop and report blocked if:
- The issue is ambiguous, blocked by missing credentials, or expands into high-risk scope.
- You cannot complete verification successfully.
- The issue needs full decomposition into focused follow-up issues.

If stopped blocked, write `$ACP_RUN_DIR/issue-comment.md` with a blocker summary, then:
```bash
cat > "$ACP_RESULT_FILE" <<'OUTER_EOF'
OUTCOME=blocked
ACTION=host-comment-blocker
ISSUE_ID={ISSUE_ID}
OUTER_EOF
```

If fully decomposed into follow-up issues, start the first line of `issue-comment.md` with exactly:
`Superseded by focused follow-up issues: #...`

# Git Rules

- Do NOT push the branch from inside the worker.
- Do NOT open a PR from inside the worker.
- Do NOT comment on the source issue with a PR URL from inside the worker.
- Exit successfully after writing the result file.
