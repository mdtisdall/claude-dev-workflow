# Shell pitfalls: macOS, Nix, and the Claude Code Bash tool

Each of these has broken a real merge, cleanup, or check script. Check new
multi-step shell commands against this list before running them.

- **The Bash tool runs the login shell, usually zsh.** zsh does not split
  unquoted variables into words (`set -- $pair` gives one word), and `status`
  is a read-only variable. For logic that needs bash, run it as
  `bash <<'EOF' ... EOF` or as a script file.
- **`/bin/bash` on macOS is bash 3.2.** It has no `declare -A`,
  `mapfile`/`readarray`, `${var,,}`, `${var^^}`, `wait -n`, or negative array
  indexes. The plugin scripts and the project hook stay 3.2-compatible. Inside
  `nix develop`, `bash` can be a newer version. Do not rely on that.
- **GNU tools inside the devShell, BSD tools outside it.** Inside, you get
  `date -d` and `stat -c`. Outside, you get `date -j -f` and `stat -f`.
  Portable scripts try the BSD form, then the GNU form.
- **`cd` persists.** A bare `cd` in one Bash call changes the directory for
  later calls. Use absolute paths, `git -C <dir>`, or `(cd <dir> && ...)`.
- **Nested quoting through `nix develop --command bash -c '...'` breaks.**
  F-strings, escaped quotes, and heredocs are the usual failures. Write a
  helper script to the scratchpad directory and run that script instead.
- **`nix develop --command` does not run direnv.** Without direnv,
  `.envrc.local` is not loaded and `GH_TOKEN` is not set, so `gh` silently
  uses the global login. Use `direnv exec . <command>` for anything that needs
  the project's environment variables.
- **A flake in a git repository sees only files that git tracks or has
  staged.** Run `git add` on a new file that the flake uses before you run
  `nix develop`.
- **The worktrees are inside the main checkout, in `.worktrees/`.** Commands
  that walk the directory tree from the main checkout, such as `grep -r`,
  `find .`, and tools that do not read `.gitignore`, also walk every task's
  worktree. Use `git grep` or `git ls-files`, or exclude `.worktrees`.
  `git clean -fdx` skips the worktrees, but `git clean -ffdx` in the main
  checkout deletes all of them.
- **The project hook sees only the command text and the session's working
  directory.** A `cd` inside a heredoc or a script is invisible to it, so a
  `git commit` for a scratch repository in such a command can be blocked as a
  commit on the default branch. Put that work in a script file in the
  scratchpad and run the file.
