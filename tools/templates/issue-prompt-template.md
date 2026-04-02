# Task

Implement issue #{ISSUE_ID} in `{REPO_SLUG}`.

# Issue Context

- Title: {ISSUE_TITLE}
- URL: {ISSUE_URL}
- Auto-merge requested: {ISSUE_AUTOMERGE}

{ISSUE_BODY}
{ISSUE_RECURRING_CONTEXT}
{ISSUE_BLOCKER_CONTEXT}

# Required Contract

Follow this order:

1. Read `AGENTS.md`, choose one narrow target, and stay within that slice.
2. If the issue is broader than one safe slice, stop and create follow-up issues instead of forcing a large patch:
   ```bash
   bash "$ACP_FLOW_TOOLS_DIR/create-follow-up-issue.sh" --parent {ISSUE_ID} --title "..." --body-file /tmp/follow-up.md
   ```
3. Implement the smallest root-cause fix in this worktree only.
4. Run the narrowest relevant local verification for the files you changed, and record every successful command with `record-verification.sh`.

- Do not default to repo-wide verification such as `pnpm test` unless the issue body explicitly requires it.
- If unrelated repo-wide suites are already red, keep the cycle focused on targeted verification for your slice and let the host verification guard decide whether publication is safe.

```bash
{ISSUE_VERIFICATION_COMMAND_SNIPPET}
```

5. Before committing, run at least:
   ```bash
   git diff --check
   test -s "$ACP_RUN_DIR/verification.jsonl" && echo "OK: verification.jsonl exists" || echo "BLOCKED: missing verification.jsonl"
   ```
6. If verification passes, commit locally and write `$ACP_RESULT_FILE`:
  ```bash
  cat > "$ACP_RESULT_FILE" <<'OUTER_EOF'
  OUTCOME=implemented
  ACTION=host-publish-issue-pr
  ISSUE_ID={ISSUE_ID}
  OUTER_EOF
  ```
7. If blocked, write `$ACP_RUN_DIR/issue-comment.md` and then write:
```bash
cat > "$ACP_RESULT_FILE" <<'OUTER_EOF'
OUTCOME=blocked
ACTION=host-comment-blocker
ISSUE_ID={ISSUE_ID}
OUTER_EOF
```

If you fully decompose the work, the first line of `issue-comment.md` must be:
`Superseded by focused follow-up issues: #...`

# Git Rules

- Do NOT push the branch from inside the worker.
- Do NOT open a PR from inside the worker.
- Do NOT comment on the source issue with a PR URL from inside the worker.
- Exit after writing the result file.
