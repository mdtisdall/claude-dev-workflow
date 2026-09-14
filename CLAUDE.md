# claude-dev-workflow

This repository is the `dev-workflow` Claude Code plugin and a marketplace
with that one plugin. `README.md` describes the skills and scripts.

- All scripts must run under macOS `/bin/bash` 3.2, with BSD tools and with the
  GNU tools of a Nix devShell. `reference/shell-pitfalls.md` lists the traps.
- The tests use local git fixtures and a fake `gh`, with no network:
  `bash tests/run-tests.sh`.
- The installed plugin is a copy, and `claude plugin update` compares only
  the `version` in `.claude-plugin/plugin.json`. A PR that changes what the
  plugin installs (skills, scripts, templates, `lib/`, `reference/`) also
  bumps that version: minor for new or changed behavior, patch for fixes and
  wording. After the merge, run
  `claude plugin marketplace update claude-dev-workflow`, then
  `claude plugin update dev-workflow@claude-dev-workflow`, then
  `/reload-plugins` or a new session.

## Branch and PR workflow

Every change to a tracked file gets to `main` through its own
branch and a reviewed pull request. There are no exceptions for documentation
or process changes: `CLAUDE.md`, `README.md`, `.envrc`, `flake.nix`,
`.gitignore`, CI configuration, and hooks also go through a branch and a PR.

One branch, one concern. Do not add an unrelated fix, chore, or doc edit to a
branch that already has work in progress. Start a new branch from
`main` for it.

The dev-workflow Claude Code plugin has the procedures: `start-task`, `ship`,
`finish-task`, `parallel-agents`, `github-token`, `project-setup`. Specific to
this project:

- Default branch: `main`. Merge method: squash.
- Checks, before each PR (CI runs the same checks):
  `nix develop --command scripts/check`
- Worktrees: one for each task, in `.worktrees/<short-name>` of the main
  checkout (git-ignored), made with the `start-task` skill. Do not create a
  worktree outside the project directory, inside another worktree, or with a
  different tool. The hook blocks `git worktree add` and `git worktree move`
  to any other path.
- Dependency sync, one time in each new worktree, before sub-agents start:
  none (the project has no dependencies to install).
- GitHub CLI: `direnv exec . gh ...`. It uses this repository's own
  fine-grained token in the git-ignored `.envrc.local`. The permissions that
  the token needs are in `.claude/gh-token-permissions`. `git` uses SSH.
- CI status: the Actions API (`ci-status.sh`, `gh run list`), not
  `gh pr checks`.
- `git commit` and `git push` to `main` are blocked for Claude
  Code by `.claude/hooks/block-main-writes.sh`. To run the git command
  yourself in a terminal is a break-glass action for a stuck state, not a
  shortcut for routine edits.
- Show the commit message and wait for approval before `git commit`. Merge
  only when told to.
