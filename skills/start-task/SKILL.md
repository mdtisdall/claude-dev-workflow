---
name: start-task
description: Start one unit of work (feature, fix, docs, or chore) on its own branch, in its own git worktree, from the latest origin default branch, so that several tasks and Claude sessions can run in parallel. Use before you change any tracked file.
---

# Start a task

One concern = one branch = one worktree = one PR. Do not add an unrelated
fix, chore, or doc edit to a branch that already has work in progress. Start
a different task for it.

## Steps

1. **Name the branch** `<type>/<short-name>`. The short name is kebab-case.

   | Type | Use |
   |---|---|
   | `feature` | New behavior |
   | `fix` | Bug fix |
   | `docs` | Documentation only |
   | `chore` | Tooling, configuration, CI, dev environment |

2. **Create the worktree.** Run this from any checkout of the repository:

   ```
   bash ${CLAUDE_PLUGIN_ROOT}/skills/start-task/scripts/new-worktree.sh <type>/<short-name>
   ```

   The script:
   - fetches `origin`;
   - creates the branch from `origin/<default>`, in
     `<main checkout>/.worktrees/<short-name>`. The location is fixed: the
     script has no directory argument;
   - adds `.worktrees/` to `.git/info/exclude` when the project does not
     git-ignore it yet;
   - links the git-ignored local files that `.worktree-links` lists from the
     main checkout (default: `.envrc.local`, the project token);
   - runs `direnv allow` in the new worktree.

   If the output says `.envrc.local` was not linked, the project has no token
   yet. Use the `github-token` skill before you use `gh`. The script links
   only when it creates the worktree, so after the token is stored, link it
   yourself: `ln -s <main checkout>/.envrc.local <wt>/.envrc.local`, then
   `direnv allow <wt>`.

3. **Work only in the worktree.** Use absolute paths into it, `git -C <wt>`,
   or `(cd <wt> && ...)`. A bare `cd` in one Bash call persists into later
   calls (see `${CLAUDE_PLUGIN_ROOT}/reference/shell-pitfalls.md`).

4. **Sync dependencies one time**, before you start sub-agents. Parallel syncs
   interfere with each other. Use the project's sync command from `CLAUDE.md`,
   for example `(cd <wt> && nix develop --command uv sync)`.

5. **Get the decisions first.** If the task has open design decisions, ask the
   user (AskUserQuestion) before you write code.

6. **Planning documents stay on the branch.** Before the merge, move lasting
   content into the permanent documentation and delete the planning file.

## Rules

- Every worktree of the project is directly in `<main checkout>/.worktrees/`.
  Do not create a worktree outside the project directory or inside another
  worktree, and do not use a different worktree tool: other tools choose their
  own location and do not link `.envrc.local`. The project hook blocks
  `git worktree add` and `git worktree move` to any other path.
- Do not run `git checkout <default>` or `git switch <default>` in a worktree.
  The default branch can be checked out in a different worktree or session.
  Base new work on `origin/<default>`.
- `.worktree-links` (optional, committed): one git-ignored path on each line,
  for example `.envrc.local` or `data`. The script does not link tracked
  paths.
- To split a task across sub-agents, use the `parallel-agents` skill.
- When the work is ready, use the `ship` skill.
