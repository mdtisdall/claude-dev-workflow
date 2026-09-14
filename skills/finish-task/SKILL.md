---
name: finish-task
description: 'Merge an approved pull request and clean up after it - confirm CI through the Actions API, squash-merge with gh, verify the merge, then remove the worktree and delete the local and remote branch. Use only when the user explicitly tells you to merge a specific PR (for example "merge #12 and delete the branch"). Also covers rebasing a second PR that conflicts on a lockfile.'
---

# Finish a task

A merge and a branch deletion are permanent. Do them only when the user gives
an explicit instruction that names the PR. The cleanup (step 4) needs the same
instruction to include deleting the branch. If it does not, ask.

Run these steps from a checkout that is not on the PR's branch, normally the
main checkout. In the steps, `S` is
`${CLAUDE_PLUGIN_ROOT}/skills/finish-task/scripts`.

## Steps

1. **CI must pass.** This command must exit 0:

   ```
   direnv exec . bash ${CLAUDE_PLUGIN_ROOT}/skills/ship/scripts/ci-status.sh <pr>
   ```

   If it does not, report the result and stop.

2. **The PR must be mergeable.** Run
   `direnv exec . gh pr view <pr> --json state,mergeable,mergeStateStatus,baseRefName,headRefName`.
   If `mergeable` is `CONFLICTING`, do the procedure in "Update a branch"
   (below) first.

3. **Merge.** Use the merge method from `CLAUDE.md`; the default is squash:

   ```
   direnv exec . gh pr merge <pr> --squash
   ```

   Do not use `--delete-branch`. It tries to check out the default branch
   locally, which fails when a different worktree has it. Step 4 deletes the
   branch.

4. **Clean up.** First do a dry run, and show the plan to the user:

   ```
   direnv exec . bash $S/cleanup-merged.sh <pr> --dry-run
   ```

   Then run the same command without `--dry-run`. The script:
   - refuses, and changes nothing, if the PR is not merged, if the local
     branch has commits that are not the PR head, or if the worktree has
     uncommitted or untracked changes;
   - verifies that each file the PR changed is the same in the merge commit;
   - removes the worktree, deletes the local branch and the remote branch,
     and fast-forwards the checkout of the default branch.

   When the script refuses, tell the user why. Do not force anything, and do
   not delete the changes that caused the refusal.

5. **Report** the merge commit, what was removed, and the new position of the
   default branch.

## Update a branch that conflicts or is behind

A common cause: two PRs change the same lockfile (`uv.lock`, `flake.lock`,
`package-lock.json`). After the first PR merges, in the worktree of the second:

1. `git fetch origin && git rebase origin/<default>`.
2. For a lockfile conflict, take the default branch's version, then
   regenerate the lockfile with its tool (`uv lock`, `nix flake lock`). Do
   not merge a lockfile by hand.
3. Check that the lockfile is consistent (for example `uv lock --check`), then
   run all the checks.
4. Get approval, then `git push --force-with-lease`.
5. Wait for CI (`ci-status.sh <pr> --wait`), then merge with the steps above.
