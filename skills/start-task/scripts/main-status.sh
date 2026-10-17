#!/usr/bin/env bash
# Report the CI result of the latest pushes to the default branch, from the
# Actions API. It only informs: a red default branch does not stop new work.
#
#   direnv exec . bash main-status.sh
#
# For each workflow, it reports the newest finished run on a push to the
# default branch (a cancelled run does not count: a newer merge replaced it),
# and whether a newer run is in progress.
#
# Exit: 0 each workflow passed; 1 a workflow failed; 2 no finished runs, or
# the API cannot be read.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../../../lib/common.sh
. "$here/../../../lib/common.sh"

case "${1:-}" in
  -h | --help)
    sed -n '2,13p' "$0"
    exit 0
    ;;
  '') ;;
  *) die "usage: main-status.sh" ;;
esac

slug="$(repo_slug)" || die "origin is not a GitHub remote"
base="$(default_branch)"

if ! runs="$(gh api "repos/$slug/actions/runs?branch=$base&event=push&per_page=50" \
  -q '.workflow_runs[] | [.name, .status, (.conclusion // "-"), .head_sha[0:7], .html_url] | @tsv' 2>/dev/null)"; then
  echo "main-status: cannot read the Actions runs of $base (is GH_TOKEN set? run this through 'direnv exec .')"
  exit 2
fi

# The API lists the newest runs first.
report="$(printf '%s\n' "$runs" | awk -F'\t' '
  NF < 5 { next }
  $2 != "completed" { if (!($1 in done) && !($1 in busy)) busy[$1] = $4; next }
  $3 == "cancelled" || $3 == "skipped" { next }
  !($1 in done) { done[$1] = $3; sha[$1] = $4; url[$1] = $5; order[++n] = $1 }
  END {
    for (i = 1; i <= n; i++) {
      w = order[i]
      line = sprintf("%-10s %s at %s  %s", done[w], w, sha[w], url[w])
      if (w in busy) line = line sprintf("  (a newer run, at %s, is in progress)", busy[w])
      print line
    }
  }')"

if [ -z "$report" ]; then
  echo "main-status: no finished CI runs on $base yet"
  exit 2
fi
echo "CI on $base:"
printf '%s\n' "$report" | sed 's/^/  /'
if printf '%s\n' "$report" | grep -Eqv '^(success|neutral) '; then
  echo "main-status: $base is red. New work can start, but a test can fail for a reason that is not in your change."
  exit 1
fi
exit 0
