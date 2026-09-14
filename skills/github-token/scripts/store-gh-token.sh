#!/usr/bin/env bash
# Store this project's GitHub fine-grained token as GH_TOKEN in .envrc.local.
#
# Run it YOURSELF, in a terminal, from anywhere in the repository. It reads a
# secret. Do not paste the token into a Claude chat.
#
#   bash store-gh-token.sh
#
# - Writes the main checkout's .envrc.local. Worktrees link to that file.
# - Refuses unless .envrc.local is git-ignored.
# - Replaces an existing GH_TOKEN line and keeps all other lines.
# - Writes mode 600, then runs `direnv allow`.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../../../lib/common.sh
. "$here/../../../lib/common.sh"

main="$(main_worktree 2>/dev/null)" || main=""
[ -n "$main" ] || die "run this from inside the project's git repository"
cd "$main"

if ! git check-ignore -q .envrc.local; then
  die ".envrc.local is not git-ignored in $main. Add .envrc.local to .gitignore (or .git/info/exclude) first; nothing written."
fi

slug="$(repo_slug || echo "this repository")"
printf 'Paste the fine-grained token for %s (input hidden): ' "$slug" >&2
IFS= read -rs token || true
printf '\n' >&2
token="$(printf '%s' "$token" | tr -d '[:space:]')"

case "$token" in
  github_pat_?*) ;;
  *) die "that is not a fine-grained personal access token (prefix github_pat_); nothing written" ;;
esac

umask 077
tmp="$(mktemp .envrc.local.XXXXXX)"
trap 'rm -f "$tmp"' EXIT
if [ -f .envrc.local ]; then
  grep -v '^[[:space:]]*export[[:space:]][[:space:]]*GH_TOKEN=' .envrc.local >"$tmp" || true
fi
printf 'export GH_TOKEN="%s"\n' "$token" >>"$tmp"
token=""
chmod 600 "$tmp"
mv "$tmp" .envrc.local
trap - EXIT

echo "Wrote GH_TOKEN to $main/.envrc.local (mode 600)."
if [ -z "${DEV_WORKFLOW_SKIP_DIRENV:-}" ] && [ -f .envrc ] && command -v direnv >/dev/null 2>&1; then
  direnv allow .
fi
echo "Next: ask Claude to validate the token (check-gh-token.sh)."
