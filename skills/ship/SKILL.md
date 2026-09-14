---
name: ship
description: Take a finished task branch to an open pull request - scope check, full checks through nix develop, commit message approval, SSH push, gh pr create with the project token, and the CI result from the Actions API. Use when the work on a branch is ready for review.
---

# Ship a branch

Work in the task's worktree. In the steps, `S` is
`${CLAUDE_PLUGIN_ROOT}/skills/ship/scripts`, and `<default>` is the default
branch (normally `main`).

## Steps

1. **Check the scope.** Make sure that the branch is not the default branch.
   Run `git fetch origin`, then `git diff --stat origin/<default>...HEAD` and
   `git status --short`. Each change must be part of this task. Move an
   unrelated change to a different task (see the `start-task` skill). Do not
   put it in this PR. Planning files that belong only to this branch must be
   gone.

2. **Review the diffs from sub-agents.** Read each sub-agent diff yourself
   before you run the checks (see the `parallel-agents` skill).

3. **Run all the checks.** If the project has `scripts/check`, run
   `nix develop --command scripts/check` in the worktree. If not, run the
   check command from `CLAUDE.md`. All checks must pass. If one fails,
   correct the problem and run the checks again. Do not ship a failing
   branch.

4. **Get approval.** Write the commit message in the repository's style (see
   `git log --oneline -15`; usually `<type>: <summary>`). In the body, tell
   what changed and why. End the message with the attribution trailer that
   your instructions require. Show the user:
   - the full commit message,
   - the list of files,
   - the PR title and body.

   Wait for an explicit approval. That approval is for the commit, the push,
   and the PR of this branch only.

5. **Commit and push.** Stage the files by explicit path. Do not use
   `git add -A`, so that stray files do not get in. Then
   `git push -u origin <branch>`. The push uses SSH and needs no token.

6. **Open the PR.** Write the body to a file in the scratchpad directory, then:

   ```
   direnv exec . gh pr create --base <default> --head <branch> --title "<title>" --body-file <file>
   ```

   Give the PR URL to the user.

7. **Get the CI result.** Run this in the background (`run_in_background`):

   ```
   direnv exec . bash $S/ci-status.sh <pr-number> --wait 30
   ```

   When it finishes, report success, or give the URLs of the failed runs.
   Exit codes: 0 success, 1 failure, 2 in progress or no runs, 3 timeout.
   Do not use `gh pr checks`. Fine-grained tokens cannot read the Checks API,
   so it always fails with "Resource not accessible by personal access token".
   `ci-status.sh` uses the Actions API.

8. **If CI fails**, read the log:
   `direnv exec . gh run view <run-id> --log-failed`. Correct the problem on
   the branch, run the checks again, show the new commit message for
   approval, and push.

## Rules

- Amend or force-push only with approval. Use `--force-with-lease`, not
  `--force`.
- Merge only when the user tells you to. Use the `finish-task` skill.
