#!/usr/bin/env bash
# Report the GitHub Actions results for the head commit of a pull request.
#
# This script uses the Actions API because fine-grained tokens cannot read the
# Checks API: `gh pr checks` fails with "Resource not accessible by personal
# access token". Run it from a checkout of the repository, through direnv, so
# that GH_TOKEN is set:
#
#   direnv exec . bash ci-status.sh [<pr-number> | <branch>] [--wait [<minutes>]]
#
# With no PR, it uses the PR of the current branch. Only the newest run of each
# workflow counts, so a passing re-run replaces an earlier failure. --wait
# polls every 30 seconds (default limit: 30 minutes).
#
# Exit: 0 all runs succeeded; 1 a run failed; 2 in progress, or no runs yet
# (without --wait); 3 --wait reached its limit.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../../../lib/common.sh
. "$here/../../../lib/common.sh"

target=""
wait_minutes=0
while [ $# -gt 0 ]; do
  case "$1" in
    --wait)
      wait_minutes=30
      case "${2:-}" in
        '' | *[!0-9]*) ;;
        *)
          wait_minutes="$2"
          shift
          ;;
      esac
      ;;
    -h | --help)
      sed -n '2,18p' "$0"
      exit 0
      ;;
    -*) die "unknown option: $1" ;;
    *) target="$1" ;;
  esac
  shift
done

slug="$(repo_slug)" || die "origin is not a GitHub remote"
pr_info="$(gh pr view ${target:+"$target"} --json number,url,headRefOid \
  -q '[.number, .url, .headRefOid] | @tsv')" \
  || die "cannot read the pull request (is GH_TOKEN set? run this through 'direnv exec .')"
IFS=$'\t' read -r number url sha <<EOF
$pr_info
EOF
[ -n "$sha" ] || die "the pull request has no head commit"

echo "PR #$number  $url"
echo "head $sha"

deadline=$(($(date +%s) + wait_minutes * 60))
while :; do
  runs="$(gh api "repos/$slug/actions/runs?head_sha=$sha&per_page=100" \
    -q '.workflow_runs[] | [.name, .status, (.conclusion // "-"), .html_url] | @tsv' \
    | awk -F'\t' '!seen[$1]++')" \
    || die "cannot list the Actions runs (the token needs actions=read)"

  state=success
  if [ -z "$runs" ]; then
    state=none
  else
    while IFS=$'\t' read -r _name status conclusion _link; do
      if [ "$status" != completed ]; then
        [ "$state" = failure ] || state=pending
      else
        case "$conclusion" in
          success | skipped | neutral) ;;
          *) state=failure ;;
        esac
      fi
    done <<EOF
$runs
EOF
  fi

  case "$state" in
    success | failure) break ;;
  esac
  if [ "$wait_minutes" -eq 0 ] || [ "$(date +%s)" -ge "$deadline" ]; then
    break
  fi
  sleep 30
done

if [ -n "$runs" ]; then
  printf '%s\n' "$runs" | awk -F'\t' '{ printf "  %-28s %-12s %-10s %s\n", $1, $2, $3, $4 }'
fi

case "$state" in
  success)
    echo "CI: success"
    exit 0
    ;;
  failure)
    echo "CI: failure"
    exit 1
    ;;
  pending)
    if [ "$wait_minutes" -gt 0 ]; then
      echo "CI: still in progress after $wait_minutes minutes"
      exit 3
    fi
    echo "CI: in progress"
    exit 2
    ;;
  none)
    if [ "$wait_minutes" -gt 0 ]; then
      echo "CI: no runs for this commit after $wait_minutes minutes"
      exit 3
    fi
    echo "CI: no runs for this commit yet"
    exit 2
    ;;
esac
