# claude-dev-workflow

`dev-workflow` is a Claude Code plugin for a workflow with one branch for each
change:

- Each change gets to the default branch through its own branch, its own git
  worktree, and a reviewed pull request.
- Each project has its **own** GitHub fine-grained token. The token can access
  only that one repository, and it is validated against the permissions that
  the project declares.
- Tools come from a Nix devShell. `gh` runs through direnv. `git` uses SSH.
- Several tasks can run at the same time, each in its own worktree in the
  project's git-ignored `.worktrees/` directory. Worktrees are never made
  outside the project directory. In one task, sub-agents work on different
  files.

This repository is also a marketplace with this one plugin.

## Install

```bash
claude plugin marketplace add ~/dev/claude-dev-workflow
```

```bash
claude plugin install dev-workflow@claude-dev-workflow
```

In an interactive session, you can use `/plugin marketplace add
~/dev/claude-dev-workflow` and `/plugin install
dev-workflow@claude-dev-workflow`. If a change to the plugin does not show,
run `/plugin marketplace update claude-dev-workflow`, then `/reload-plugins`
or restart the session.

## Skills

Invoke a skill as `/dev-workflow:<skill>`, or let Claude select it from its
description.

| Skill | Use |
|---|---|
| `project-setup` | Bring a repository onto the workflow: token first, then `.envrc`, `.gitignore`, `gh` in the flake, the hook, the permissions manifest, `scripts/check`, and `CLAUDE.md`, all through a PR. Also updating a project after the templates change. |
| `github-token` | Create, store, and validate the project's own fine-grained token. |
| `start-task` | Make a `<type>/<name>` branch in a new worktree, `.worktrees/<name>`, from `origin/<default>`. |
| `ship` | Scope check, all checks, commit approval, push, PR, CI result. |
| `finish-task` | After an explicit instruction: merge, verify, remove the worktree and branches. Also rebasing a PR after a lockfile conflict. |
| `parallel-agents` | File ownership, model tiers, and prompts for sub-agents; review of each diff; byte-for-byte comparison for refactors. |
| `browser-check-localhost` | Check generated HTML pages in the Browser pane through a temporary localhost server. |

`reference/shell-pitfalls.md` lists the macOS, Nix, and Bash-tool traps that
the scripts avoid.

## One token for each project

A project does not use a shared or global `GH_TOKEN`:

1. The project commits `.claude/gh-token-permissions`, one `permission=level`
   on each line (default: `metadata=read`, `contents=write`,
   `pull_requests=write`, `actions=read`).
2. `token-url.sh` prints a link to GitHub's token form, with the name, owner,
   expiry, and those permissions filled in. The user selects
   **Only select repositories** and then the repository.
3. The user runs `store-gh-token.sh` in their own terminal. The script writes
   `export GH_TOKEN=...` to the main checkout's git-ignored `.envrc.local`, with
   mode 600. Claude never sees the token.
4. `direnv exec . bash check-gh-token.sh` does a check of the local setup (file
   ignored, mode, `.envrc` loads it, fine-grained prefix), the repository
   access, and the expiry. Then it sends a request for each declared permission
   and reports the permission names that are missing, from GitHub's
   `X-Accepted-GitHub-Permissions` header.

New worktrees get a link to the main checkout's `.envrc.local`, so one token
serves all worktrees of that project.

## Scripts

All scripts are compatible with bash 3.2 and run from inside the target
repository.

| Script | Purpose |
|---|---|
| `skills/github-token/scripts/token-url.sh` | Pre-filled token creation link |
| `skills/github-token/scripts/store-gh-token.sh` | Store the token (the user runs it) |
| `skills/github-token/scripts/check-gh-token.sh` | Validate the token against the manifest |
| `skills/start-task/scripts/new-worktree.sh` | Branch and worktree in `.worktrees/`, with local-file links |
| `skills/ship/scripts/ci-status.sh` | CI result from the Actions API (`--wait` to poll) |
| `skills/finish-task/scripts/cleanup-merged.sh` | Safe cleanup after a merge (`--dry-run`) |
| `skills/project-setup/templates/block-main-writes.sh` | Project hook: blocks commits and pushes to the default branch, and worktrees outside `.worktrees/` |

## Development

```bash
nix develop --command scripts/check
```

`scripts/check` runs the tests under `/bin/bash`, shellcheck, and
`claude plugin validate --strict .` when a `claude` CLI is on PATH. The tests
use local git fixtures and a fake `gh` (`tests/fake-bin/gh`), with no network.
