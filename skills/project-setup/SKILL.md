---
name: project-setup
description: Bring a repository onto the dev-workflow - its own GitHub fine-grained token first, then .envrc/.gitignore/flake gh, the hook that blocks commits and pushes to the default branch, the token permissions manifest, a single check command, CI that runs only the affected tests on PRs for Python projects, and the workflow section of CLAUDE.md, all merged through a PR. Use when you start a new project or move an existing repository onto this workflow.
---

# Project setup

Templates are in `${CLAUDE_PLUGIN_ROOT}/skills/project-setup/templates/`.
The result:

| File | Purpose | Tracked |
|---|---|---|
| `.claude/gh-token-permissions` | Permissions that this project's token needs | yes |
| `.envrc` | `use flake`; loads `.envrc.local`; warns when `GH_TOKEN` is not set | yes |
| `.envrc.local` | `export GH_TOKEN=...` for this repository only | **no** (git-ignored, mode 600) |
| `.gitignore` | Ignores `.direnv/`, `.envrc.local*`, and `.worktrees/` | yes |
| `.worktrees/<short-name>` | One worktree for each task, inside the project directory | **no** (git-ignored) |
| `flake.nix` | The devShell supplies `gh` and the project toolchain | yes |
| `.claude/settings.json`, `.claude/hooks/block-main-writes.sh` | Blocks Claude's commits and pushes to the default branch, and worktrees outside `.worktrees/` | yes |
| `.claude/hooks/devshell-gh.sh` | Makes a plain `gh` in Claude's Bash commands the devShell's `gh`, with the project token | yes |
| `scripts/check` | One command for all lint, format, type, and test checks; `--changed-since <ref>` runs only the affected tests | yes |
| `scripts/affected-tests` | Python projects: selects the tests that a change can affect | yes |
| `.github/workflows/check.yml` | Python projects: CI with the affected tests on PRs, and all the tests on the default branch after each merge | yes |
| `CLAUDE.md` | The "Branch and PR workflow" section | yes |

## Before you start

Check each item. Report each problem to the user, and stop until it is
resolved.

1. **GitHub remote over SSH.** `origin` is `git@github.com:<owner>/<repo>.git`.
   If it uses HTTPS, suggest
   `git remote set-url origin git@github.com:<owner>/<repo>.git`.
   If the GitHub repository does not exist, the user creates it on GitHub.
   The first commit of an empty repository is the one direct push to the
   default branch. Do it before you install the hook.
2. **Tools.** `nix` and `direnv` are on PATH.
3. **Existing files.** Read `.envrc`, `.gitignore`, `flake.nix`, `CLAUDE.md`,
   and the CI configuration before you change them. Merge the new content into
   them. Do not overwrite them.

## Steps

1. **Protect the secret file first.** If `git check-ignore -q .envrc.local`
   fails, add `.envrc.local` and `.envrc.local.*` to `.git/info/exclude`. That
   file is local and untracked, and it applies to all worktrees. Step 4 adds
   the same lines to `.gitignore`.

2. **Get the token.** Do steps 1-3 of the `github-token` skill: confirm the
   permissions with the user, give the pre-filled link, and have the user
   store the token. The project has no manifest yet, so `token-url.sh` uses
   the plugin default. Record the permissions the user adds, for step 4.

3. **Make the branch.** Run
   `bash ${CLAUDE_PLUGIN_ROOT}/skills/start-task/scripts/new-worktree.sh chore/adopt-dev-workflow`.
   The worktree is `.worktrees/adopt-dev-workflow` in the main checkout. The
   script adds `.worktrees/` to `.git/info/exclude` until step 4 puts it in
   `.gitignore`, and it links the `.envrc.local` from step 2. Do all the next
   work in the worktree that the script prints.

4. **Add the files** on the branch:
   - `.gitignore`: add the lines from `templates/gitignore` that are missing.
   - `.envrc`: merge `templates/envrc`. Keep the lines that are there.
   - `flake.nix`: make sure that `pkgs.gh` is in the devShell packages. If the
     project has no flake, ask the user which toolchain it needs before you
     write one.
   - `.claude/gh-token-permissions`: copy
     `${CLAUDE_PLUGIN_ROOT}/skills/github-token/gh-token-permissions.default`,
     and add the permissions from step 2.
   - `.claude/hooks/block-main-writes.sh` and `.claude/hooks/devshell-gh.sh`:
     copy them from `templates/` and `chmod +x` them. Merge
     `templates/settings.json` into `.claude/settings.json`: the
     `PreToolUse` hook, and the `SessionStart` and `CwdChanged` hooks.
   - `scripts/check`: start from `templates/check`. Put in the project's real
     lint, format, type-check, and test commands (read the CI configuration
     and the documentation; ask the user if they are not clear). `chmod +x` it.
     If the project has CI, make CI run the same commands. Tools that search
     the directory tree without `.gitignore` also search `.worktrees/`: exclude
     it.
   - Python projects with pytest: copy `templates/affected-tests` to
     `scripts/affected-tests` and `chmod +x` it. In `scripts/check`, run the
     tests through it when `--changed-since` is given (the example in
     `templates/check`). Run
     `python3 scripts/affected-tests --base origin/<default> --explain` on a
     branch with a typical change, and read the reasons. Add project files
     that the defaults do not cover to `[tool.affected-tests]` in
     `pyproject.toml` (the settings are at the top of the script): a data
     file that tests read through a computed path goes in `map`, a file that
     needs no tests goes in `ignore`. A file that matches no rule and that no
     module names runs all the tests.
   - Python projects with GitHub Actions: start from `templates/check.yml` for
     `.github/workflows/check.yml`. Merge it with the CI that is there. Replace
     `main` if the default branch has a different name. Keep the `changes`
     job, the conditions on the `check` job, the `concurrency` block, and the
     `report-main` job. If a branch ruleset requires status checks, require
     `changes` and `check`: a skipped job counts as passed. Projects in other
     languages keep one CI job that runs `scripts/check`.
   - `CLAUDE.md`: add `templates/claude-md-workflow.md` as a section, and
     replace each `<placeholder>`. Keep the content that is there.

5. **Validate the token** in the worktree: `direnv allow <worktree>`, then do
   step 4 of the `github-token` skill. Continue only when the check has no
   `FAIL`.

6. **Run the checks:** `(cd <worktree> && nix develop --command scripts/check)`.

7. **Ship** with the `ship` skill. Merge with the `finish-task` skill when the
   user tells you to.

8. **Recommend a branch ruleset.** The hook stops only Claude. A GitHub ruleset
   stops everyone. Tell the user that they can add one on GitHub: Settings >
   Rules > Rulesets > require a pull request before merging, on the default
   branch. Do not change repository settings yourself.

9. **Report the worktrees outside `.worktrees/`.** Run `git worktree list`.
   Give the user each worktree that is not in `<main checkout>/.worktrees/`.
   Do not move or remove one yourself: a session can be working in it. The
   user can finish its PR first, or move it after the work is committed:
   `git -C <main checkout> worktree move <old path> .worktrees/<short-name>`.

## Update a project that already uses the workflow

When the plugin's templates change, update the project on its own
`chore/<short-name>` branch: copy `templates/block-main-writes.sh` and
`templates/devshell-gh.sh` again, merge `templates/settings.json`, add
the missing lines from `templates/gitignore`, and merge the changes of
`templates/claude-md-workflow.md` into `CLAUDE.md`. In a Python project, copy
`templates/affected-tests` again, and merge the changes of
`templates/check.yml` and of the `--changed-since` part of `templates/check`. Then run the checks and
ship. Step 9 applies after the merge.
