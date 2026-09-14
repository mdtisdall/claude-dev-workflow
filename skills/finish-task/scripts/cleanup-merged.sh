#!/usr/bin/env bash
# Clean up after a merged pull request: remove its worktree, delete its local
# branch and its remote branch, and fast-forward the default branch checkout.
#
#   direnv exec . bash cleanup-merged.sh <pr-number> [--dry-run]
#
# Run it from a checkout that is not on the PR's branch (normally the main
# checkout). It refuses, and changes nothing, unless:
#   - the PR is MERGED;
#   - the local branch (if any) points at the PR's head commit, so that no
#     local commit is lost;
#   - the branch's worktree (if any) has no uncommitted or untracked changes.
# It never forces anything. --dry-run shows the commands without running them.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../../../lib/common.sh
. "$here/../../../lib/common.sh"

pr=""
dry_run=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry_run=1 ;;
    -h | --help)
      sed -n '2,15p' "$0"
      exit 0
      ;;
    '' | *[!0-9]*) die "usage: cleanup-merged.sh <pr-number> [--dry-run]" ;;
    *) pr="$1" ;;
  esac
  shift
done
[ -n "$pr" ] || die "usage: cleanup-merged.sh <pr-number> [--dry-run]"

git rev-parse --git-dir >/dev/null 2>&1 || die "not inside a git repository"

info="$(gh pr view "$pr" --json state,headRefName,headRefOid,mergeCommit \
  -q '[.state, .headRefName, .headRefOid, (.mergeCommit.oid // "")] | @tsv')" \
  || die "cannot read PR #$pr (run this through 'direnv exec .')"
IFS=$'\t' read -r state branch head merge <<EOF
$info
EOF

[ "$state" = MERGED ] || die "PR #$pr is $state, not MERGED; nothing changed"
[ -n "$branch" ] && [ -n "$head" ] || die "PR #$pr has no head branch information; nothing changed"

base="$(default_branch)"
[ "$branch" != "$base" ] || die "the PR's head branch is the default branch; nothing changed"

main="$(main_worktree)"
wt="$(worktree_for_branch "$branch")"
current="$(git rev-parse --show-toplevel)"
if [ -n "$wt" ]; then
  [ "$wt" != "$main" ] || die "$branch is checked out in the main checkout ($main); switch that checkout to $base first; nothing changed"
  [ "$wt" != "$current" ] || die "run this from a different checkout, not from the $branch worktree; nothing changed"
fi

local_tip=""
if git show-ref --verify --quiet "refs/heads/$branch"; then
  local_tip="$(git rev-parse "refs/heads/$branch")"
  if [ "$local_tip" != "$head" ]; then
    die "local $branch is at ${local_tip:0:12}, but the head of PR #$pr is ${head:0:12}: the local branch has commits that are not in the PR; nothing changed"
  fi
fi

if [ -n "$wt" ]; then
  dirty="$(git -C "$wt" status --porcelain --untracked-files=all)"
  [ -z "$dirty" ] || die "the worktree $wt has uncommitted or untracked changes; nothing changed:
$dirty"
fi

git fetch --quiet --prune origin
remote_exists=0
if git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
  remote_exists=1
fi

# Every file that the PR changed must be the same in the merge commit.
if [ -n "$merge" ] && git cat-file -e "$head^{commit}" 2>/dev/null \
  && git cat-file -e "$merge^{commit}" 2>/dev/null; then
  fork="$(git merge-base "$merge^" "$head" 2>/dev/null || true)"
  changed=""
  [ -z "$fork" ] || changed="$(git diff --name-only "$fork" "$head")"
  differ=""
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    git diff --quiet "$head" "$merge" -- "$f" || differ="$differ $f"
  done <<EOF
$changed
EOF
  if [ -z "$differ" ]; then
    echo "verified: each file that PR #$pr changed is the same in the merge commit ${merge:0:12}"
  else
    echo "note: these files are different in the PR head and the merge commit (expected only if $base also changed them):$differ"
  fi
else
  echo "note: the merge commit is not available locally; content verification skipped"
fi

run() {
  printf '+ %s\n' "$*"
  [ "$dry_run" -eq 1 ] || "$@"
}

[ -z "$wt" ] || run git worktree remove "$wt"
[ -z "$local_tip" ] || run git branch -D "$branch"
[ "$remote_exists" -eq 0 ] || run git push origin --delete "$branch"
run git worktree prune

base_wt="$(worktree_for_branch "$base")"
if [ -z "$base_wt" ]; then
  echo "note: $base is not checked out in a worktree; nothing to fast-forward"
elif [ -n "$(git -C "$base_wt" status --porcelain --untracked-files=no)" ]; then
  echo "note: $base_wt has local changes; fast-forward $base there yourself"
else
  run git -C "$base_wt" merge --ff-only --quiet "origin/$base"
fi

if [ "$dry_run" -eq 1 ]; then
  echo "dry run: nothing changed"
else
  echo "done: PR #$pr cleaned up"
fi
