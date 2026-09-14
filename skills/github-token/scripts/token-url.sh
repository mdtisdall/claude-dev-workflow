#!/usr/bin/env bash
# Print a link to GitHub's "new fine-grained token" form, filled in for this
# repository: name, description, resource owner, expiry, and each permission in
# the project's manifest. GitHub cannot pre-select repository access, so the
# user must still select "Only select repositories" and this repository.
#
#   bash token-url.sh [--days <1-366>] [--manifest <file>]
#
# The manifest is .claude/gh-token-permissions. When the project has no
# manifest yet, the script uses the plugin's gh-token-permissions.default.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../../../lib/common.sh
. "$here/../../../lib/common.sh"

days=90
manifest=""
while [ $# -gt 0 ]; do
  case "$1" in
    --days)
      [ $# -ge 2 ] || die "--days needs a number"
      days="$2"
      shift
      ;;
    --manifest)
      [ $# -ge 2 ] || die "--manifest needs a file"
      manifest="$2"
      shift
      ;;
    -h | --help)
      sed -n '2,11p' "$0"
      exit 0
      ;;
    *) die "unknown argument: $1" ;;
  esac
  shift
done

case "$days" in
  '' | *[!0-9]*) die "--days must be a number from 1 to 366" ;;
esac
if [ "$days" -lt 1 ] || [ "$days" -gt 366 ]; then
  die "--days must be a number from 1 to 366"
fi

top="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
slug="$(cd "$top" && repo_slug)" || die "origin is not a GitHub remote"
owner="${slug%%/*}"
repo="${slug#*/}"

if [ -z "$manifest" ]; then
  manifest="$top/.claude/gh-token-permissions"
  [ -f "$manifest" ] || manifest="$here/../gh-token-permissions.default"
fi
[ -f "$manifest" ] || die "no permissions manifest: $manifest"

urlencode() {
  local s="$1" out="" c i
  for ((i = 0; i < ${#s}; i++)); do
    c="${s:i:1}"
    case "$c" in
      [A-Za-z0-9._~-]) out="$out$c" ;;
      *) out="$out$(printf '%%%02X' "'$c")" ;;
    esac
  done
  printf '%s' "$out"
}

name="$repo-claude"
name="${name:0:40}"
description="gh CLI for $slug (dev-workflow plugin)"

url="https://github.com/settings/personal-access-tokens/new"
url="$url?name=$(urlencode "$name")"
url="$url&description=$(urlencode "$description")"
url="$url&target_name=$(urlencode "$owner")"
url="$url&expires_in=$days"

listed=""
entries="$(sed -e 's/#.*//' -e 's/[[:space:]]//g' -e '/^$/d' "$manifest")"
while IFS= read -r entry; do
  [ -n "$entry" ] || continue
  perm="${entry%%=*}"
  level="${entry#*=}"
  case "$perm" in
    '' | *[!a-z_]*) die "bad permission name in $manifest: $entry" ;;
  esac
  case "$level" in
    read | write | admin) ;;
    *) die "bad level in $manifest: $entry" ;;
  esac
  url="$url&$perm=$level"
  listed="$listed $perm=$level"
done <<EOF
$entries
EOF

cat <<EOF
Open this link to create the token. Examine every field before you generate it.

  $url

On the form:
  1. Repository access: select "Only select repositories", then $slug only.
     (The link cannot fill in this field.)
  2. Permissions must be exactly:$listed
     (Metadata: read-only is always added.)
  3. Generate the token and copy it. Do not paste it into Claude.
     Store it with store-gh-token.sh in your own terminal.

If $owner is an organization that requires approval for tokens, the token
stays pending until an organization admin approves it.
EOF
