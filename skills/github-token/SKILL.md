---
name: github-token
description: Create, store, and validate this project's own GitHub fine-grained personal access token (GH_TOKEN in the git-ignored .envrc.local), checked against the permissions in .claude/gh-token-permissions. Use when setting up a project, in a new clone or on a new machine, when gh returns 401/403/404 or "Could not resolve to a Repository", or when the token is near expiry.
---

# Per-project GitHub token

Each project has its own fine-grained token. The token can access only that
one repository, and has only the permissions that the project lists in
`.claude/gh-token-permissions`. Do not share a token between projects. Do not
use a global token. `git` uses SSH and needs no token. The token is for `gh`
only.

`gh` uses `GH_TOKEN` in preference to its keyring login. When `GH_TOKEN` is
not set, `gh` silently uses the global account, which has the wrong access.
Thus, run every `gh` command as `direnv exec . gh ...`. `nix develop
--command` does not run direnv, so it does not load `.envrc.local`.

## Rules

- Do not ask for, read, print, or handle the token value. Do not `cat`
  `.envrc.local`. The user types the token into `store-gh-token.sh` in their
  own terminal.
- If the user pastes a token into the chat, tell them to revoke that token and
  create a new one.
- Do not change GitHub account or organization settings. Give the user the
  steps.

In the steps, `S` is `${CLAUDE_PLUGIN_ROOT}/skills/github-token/scripts`.

## Steps

1. **Confirm the permissions.** Read `.claude/gh-token-permissions`. If the
   project does not have this file, use
   `${CLAUDE_PLUGIN_ROOT}/skills/github-token/gh-token-permissions.default`.
   Adding the file to the repository is a tracked change, so it goes through a
   branch and PR (see the `project-setup` skill). Show the list to the user
   and confirm that it covers what the project needs, and nothing more.
   Do not add a Checks permission: fine-grained tokens do not offer one,
   although a 403 from the Checks API names `checks=read`. CI status uses the
   Actions API (`actions=read`).

2. **The user creates the token.** Run `bash $S/token-url.sh` from the
   repository. Give the user the URL and the checklist that the script prints.
   The URL fills in the name, owner, expiry, and permissions. GitHub cannot
   pre-select repository access, so the user must select
   **Only select repositories** and then this repository. When the owner is an
   organization that requires approval, the token stays *pending* until an
   organization admin approves it. Until then, validation fails.

3. **The user stores the token.** Give the user this command in a `bash`
   block. Replace `${CLAUDE_PLUGIN_ROOT}` with the real absolute path, because
   the user's shell does not have that variable:

   ```
   bash <absolute S>/store-gh-token.sh
   ```

   The user runs it from anywhere in the repository. The script writes to the
   main checkout's `.envrc.local` with mode 600. It keeps the other lines in
   that file, and it runs `direnv allow`. It refuses to write when
   `.envrc.local` is not git-ignored. Worktrees link to that file (see the
   `start-task` skill).

4. **You validate the token.** From the checkout where you work:

   ```
   direnv exec . bash $S/check-gh-token.sh
   ```

   Show the result table to the user. The script sends a real request for
   each permission that the manifest declares. For a write permission, it
   sends a POST with an empty JSON body `{}`. GitHub checks the token's
   permission before it validates the body. Thus, an allowed token gets 422
   and a refused token gets 403, and the request creates nothing. Use
   `--read-only` to skip those POSTs. (Confirmed on a real repository:
   `POST pulls` and `POST git/refs` returned 422 for a token with
   `pull_requests=write` and `contents=write`, and `POST issues` returned 403
   for a token without an Issues permission, with the missing permission in
   the `X-Accepted-GitHub-Permissions` header.)

   | Result | Cause | Correction (by the user) |
   |---|---|---|
   | `FAIL ... permission refused (endpoint needs X)` | The token does not have permission X. | Edit the token's permissions on GitHub, then run the check again. |
   | `FAIL repository: not found` | The token's repository access does not include this repository, or the resource owner is wrong. | Correct the repository access, or create the token again with the correct owner. |
   | `FAIL repository refused` | The organization has not approved the token, or SSO is not authorized. | Get approval, or authorize SSO. |
   | `FAIL token rejected` (401) | The token is expired, revoked, or mistyped. | Regenerate the token and store it again (step 3). |
   | `unverified` | There is no side-effect-free probe for this permission. | Confirm the permission on the token's settings page. |

   Do the check again after each correction. Continue only when the result
   has no `FAIL`.

5. **Expiry.** When the check shows a warning that the token expires in less
   than 30 days, tell the user. To renew, the user regenerates the token on
   GitHub and does step 3 again.
