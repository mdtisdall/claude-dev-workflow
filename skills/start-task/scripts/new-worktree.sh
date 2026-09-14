#!/usr/bin/env bash
# Create a branch and a worktree for one task, based on the latest origin
# default branch.
#
#   bash new-worktree.sh <type>/<short-name> [<dir>]
#
#   <type>  feature | fix | docs | chore
#   <dir>   default: ../<repo>-<short-name>, next to the main checkout
#
# The script links each git-ignored path that .worktree-links lists (one path
# on each line; default: .envrc.local) from the main checkout into the new
# worktree, then runs `direnv allow` there. The branch has no upstream until
# the first `git push -u origin <branch>`.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../../../lib/common.sh
. "$here/../../../lib/common.sh"

[ $# -ge 1 ] && [ $# -le 2 ] || die "usage: new-worktree.sh <type>/<short-name> [<dir>]"
branch="$1"

case "$branch" in
  feature/?* | fix/?* | docs/?* | chore/?*) ;;
  *) die "the branch must be <type>/<short-name>, with type feature, fix, docs, or chore: $branch" ;;
esac
git check-ref-format --branch "$branch" >/dev/null 2>&1 || die "not a valid branch name: $branch"

main="$(main_worktree 2>/dev/null)" || main=""
[ -n "$main" ] || die "not inside a git repository"
base="$(cd "$main" && default_branch)"

short="${branch#*/}"
short="$(printf '%s' "$short" | tr '/' '-')"
dir="${2:-$(dirname "$main")/$(basename "$main")-$short}"

[ ! -e "$dir" ] || die "already exists: $dir"
if git -C "$main" show-ref --verify --quiet "refs/heads/$branch"; then
  die "the branch already exists locally: $branch"
fi

git -C "$main" fetch --quiet origin
if git -C "$main" ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
  die "the branch already exists on origin: $branch"
fi

git -C "$main" worktree add --quiet --no-track -b "$branch" "$dir" "origin/$base"
dir="$(cd "$dir" && pwd -P)"

if [ -f "$main/.worktree-links" ]; then
  links="$(sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^$/d' "$main/.worktree-links")"
else
  links=".envrc.local"
fi
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  if [ ! -e "$main/$rel" ]; then
    echo "not linked (not in the main checkout): $rel"
    continue
  fi
  if ! git -C "$main" check-ignore -q "$rel"; then
    echo "not linked (not git-ignored): $rel"
    continue
  fi
  mkdir -p "$(dirname "$dir/$rel")"
  ln -s "$main/$rel" "$dir/$rel"
  echo "linked: $rel"
done <<EOF
$links
EOF

if [ -z "${DEV_WORKFLOW_SKIP_DIRENV:-}" ] && [ -f "$dir/.envrc" ] && command -v direnv >/dev/null 2>&1; then
  direnv allow "$dir"
fi

cat <<EOF
Worktree: $dir
Branch:   $branch (from origin/$base)
Next:     sync dependencies one time in the worktree, before any sub-agents start.
EOF
