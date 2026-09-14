# Shared helpers for the dev-workflow scripts. Source it; do not run it.
# Bash 3.2 compatible (macOS /bin/bash).

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

# owner/repo from a GitHub remote URL (SSH or HTTPS). Fails for other hosts.
repo_slug() {
  local url
  url="$(git remote get-url "${1:-origin}" 2>/dev/null)" || return 1
  case "$url" in
    git@github.com:*) url="${url#git@github.com:}" ;;
    ssh://git@github.com/*) url="${url#ssh://git@github.com/}" ;;
    https://github.com/*) url="${url#https://github.com/}" ;;
    *) return 1 ;;
  esac
  url="${url%/}"
  url="${url%.git}"
  case "$url" in
    */*) printf '%s\n' "$url" ;;
    *) return 1 ;;
  esac
}

# Default branch name from origin/HEAD; "main" when origin/HEAD is not set.
default_branch() {
  local ref
  ref="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  ref="${ref#origin/}"
  printf '%s\n' "${ref:-main}"
}

# Absolute path of the main working tree, from any worktree of the repository.
main_worktree() {
  git worktree list --porcelain | sed -n '1s/^worktree //p'
}

# Path of the worktree that has refs/heads/<branch> checked out, or nothing.
worktree_for_branch() {
  git worktree list --porcelain | awk -v b="refs/heads/$1" '
    /^worktree / { path = substr($0, 10) }
    $0 == "branch " b { print path; exit }'
}
