#!/usr/bin/env bash
# Validate this project's GitHub fine-grained token (GH_TOKEN) against the
# permissions that the project declares in .claude/gh-token-permissions.
#
# Run it from a checkout of the repository, through direnv, so that
# .envrc.local is loaded:
#
#   direnv exec . bash check-gh-token.sh [--read-only] [--manifest <file>]
#
# Each declared permission gets a real API request. A read permission gets a
# GET. A write permission gets a POST with the empty JSON body `{}`. GitHub
# checks the token's permission before it validates the body: an allowed token
# gets 422 (invalid body), and a refused token gets 403. The empty body cannot
# create anything. (Confirmed 2026-09-13 on a real repository: POST pulls {}
# returned 422 for a token with pull_requests=write, and POST issues {}
# returned 403 for the same token, which had no issues permission.)
# --read-only skips the POSTs and reports write permissions as unverified.
#
# The script never prints the token. Exit 0: no failures (a permission without
# a probe is reported as "unverified"). Exit 1: one or more failures.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../../../lib/common.sh
. "$here/../../../lib/common.sh"

read_only=0
manifest=""
while [ $# -gt 0 ]; do
  case "$1" in
    --read-only) read_only=1 ;;
    --manifest)
      [ $# -ge 2 ] || die "--manifest needs a file"
      manifest="$2"
      shift
      ;;
    -h | --help)
      sed -n '2,20p' "$0"
      exit 0
      ;;
    *) die "unknown argument: $1" ;;
  esac
  shift
done

top="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
cd "$top"
[ -n "$manifest" ] || manifest="$top/.claude/gh-token-permissions"

failures=0
unverified=0
slug=""
pass() { printf '  ok          %s\n' "$*"; }
warn() { printf '  warn        %s\n' "$*"; }
fail() {
  printf '  FAIL        %s\n' "$*"
  failures=$((failures + 1))
}
unver() {
  printf '  unverified  %s\n' "$*"
  unverified=$((unverified + 1))
}

finish() {
  echo
  if [ "$failures" -gt 0 ]; then
    echo "Result: $failures problem(s). Correct them, then run this check again."
    exit 1
  fi
  echo "Result: the token is valid for $slug."
  if [ "$unverified" -gt 0 ]; then
    echo "$unverified permission(s) unverified: confirm them on the token's settings page."
  fi
  echo "The API cannot show whether the token is limited to this one repository:"
  echo "confirm \"Only select repositories\" on the token's settings page."
  exit 0
}

# --- Local setup -------------------------------------------------------------

echo "Local setup ($top)"

if slug="$(repo_slug)"; then
  pass "origin is the GitHub repository $slug"
  case "$(git remote get-url origin)" in
    https://*) warn "origin uses HTTPS; this workflow uses SSH: git remote set-url origin git@github.com:$slug.git" ;;
  esac
else
  slug=""
  fail "origin is not a GitHub remote"
fi

if git check-ignore -q .envrc.local; then
  pass ".envrc.local is git-ignored"
else
  fail ".envrc.local is not git-ignored: add .envrc.local and .envrc.local.* to .gitignore"
fi

if [ -e .envrc.local ]; then
  # GNU form first: in a Nix devShell, GNU `stat -f` means "file system status"
  # and prints unrelated output. BSD stat rejects -c.
  mode="$(stat -L -c '%a' .envrc.local 2>/dev/null || stat -L -f '%Lp' .envrc.local)"
  case "$mode" in
    600 | 400) pass ".envrc.local has mode $mode" ;;
    *) fail ".envrc.local has mode $mode: run chmod 600 on it" ;;
  esac
else
  fail ".envrc.local does not exist here (store the token with store-gh-token.sh; a worktree links to the main checkout's file)"
fi

if [ -f .envrc ] && grep -q 'envrc\.local' .envrc; then
  pass ".envrc loads .envrc.local"
else
  fail ".envrc does not load .envrc.local (add: source_env_if_exists .envrc.local)"
fi

if command -v gh >/dev/null 2>&1; then
  pass "gh is on PATH"
else
  fail "gh is not on PATH: add pkgs.gh to the flake devShell"
fi

case "${GH_TOKEN:-}" in
  "") fail "GH_TOKEN is not set: run this through 'direnv exec .' (without GH_TOKEN, gh uses your global login)" ;;
  github_pat_?*) pass "GH_TOKEN is a fine-grained personal access token" ;;
  ghp_*) fail "GH_TOKEN is a classic token: create a fine-grained token for this repository" ;;
  *) fail "GH_TOKEN is not a fine-grained personal access token (prefix github_pat_)" ;;
esac

if [ -f "$manifest" ]; then
  pass "permissions manifest: ${manifest#"$top"/}"
else
  fail "no permissions manifest at $manifest"
fi

[ "$failures" -eq 0 ] || finish

# --- Probes ------------------------------------------------------------------

probe_output=""
probe_status=""
probe_accepted=""

# Value of a response header from the last probe (case-insensitive name).
header() {
  printf '%s\n' "$probe_output" | tr -d '\r' | grep -i "^$1:" | head -n 1 \
    | sed 's/^[^:]*:[[:space:]]*//' || true
}

# probe METHOD PATH: sets probe_status and probe_accepted.
probe() {
  if [ "$1" = GET ]; then
    probe_output="$(gh api --include --method GET "$2" 2>&1)" || true
  else
    probe_output="$(printf '{}' | gh api --include --method "$1" "$2" --input - 2>&1)" || true
  fi
  probe_status="$(printf '%s\n' "$probe_output" \
    | sed -n -E 's/^HTTP\/[0-9.]+ ([0-9]{3}).*/\1/p' | head -n 1)"
  probe_accepted="$(header x-accepted-github-permissions)"
}

explain() {
  case "$1" in
    401) echo "token rejected (expired, revoked, or mistyped)" ;;
    403) echo "permission refused${probe_accepted:+ (endpoint needs $probe_accepted)}" ;;
    404) echo "not found: the token cannot see this repository (its repository access must include it)" ;;
    "") echo "no HTTP response: $(printf '%s\n' "$probe_output" | tail -n 1)" ;;
    *) echo "HTTP $1" ;;
  esac
}

# Days from now until a "YYYY-MM-DD HH:MM:SS UTC" timestamp.
days_until() {
  local when="${1% UTC}" epoch now
  epoch="$(date -u -j -f '%Y-%m-%d %H:%M:%S' "$when" +%s 2>/dev/null \
    || date -u -d "$when" +%s 2>/dev/null)" || return 1
  now="$(date -u +%s)"
  echo $(((epoch - now) / 86400))
}

echo
echo "Token access to $slug"
probe GET "repos/$slug"
case "$probe_status" in
  200) pass "the repository is visible to the token" ;;
  403) fail "repository refused: $(explain 403). If an organization owns it, the token can be pending admin approval or need SSO authorization." ;;
  *) fail "repository: $(explain "$probe_status")" ;;
esac
[ "$failures" -eq 0 ] || finish

expiry="$(header github-authentication-token-expiration)"
if [ -z "$expiry" ]; then
  warn "the token has no expiration date"
elif days="$(days_until "$expiry")"; then
  if [ "$days" -lt 30 ]; then
    warn "the token expires $expiry ($days days): regenerate it soon"
  else
    pass "the token expires $expiry ($days days)"
  fi
else
  pass "the token expires $expiry"
fi

# probe_permission NAME LEVEL
probe_permission() {
  local name="$1" level="$2" read_path="" write_path=""
  case "$level" in
    read | write | admin) ;;
    *)
      fail "$name=$level: the level must be read, write, or admin"
      return
      ;;
  esac
  case "$name" in
    metadata) read_path="repos/$slug" ;;
    contents)
      read_path="repos/$slug/commits?per_page=1"
      write_path="repos/$slug/git/refs"
      ;;
    pull_requests)
      read_path="repos/$slug/pulls?per_page=1"
      write_path="repos/$slug/pulls"
      ;;
    issues)
      read_path="repos/$slug/issues?per_page=1"
      write_path="repos/$slug/issues"
      ;;
    actions) read_path="repos/$slug/actions/runs?per_page=1" ;;
  esac

  if [ "$level" != read ] && [ -n "$write_path" ] && [ "$read_only" -eq 0 ]; then
    probe POST "$write_path"
    case "$probe_status" in
      422 | 400) pass "$name=$level" ;;
      403) fail "$name=$level: $(explain 403)" ;;
      *) unver "$name=$level: the write probe was inconclusive ($(explain "$probe_status"))" ;;
    esac
    return
  fi

  if [ -z "$read_path" ]; then
    unver "$name=$level: no side-effect-free probe for this permission"
    return
  fi
  probe GET "$read_path"
  case "$probe_status" in
    2?? | 409)
      if [ "$level" = read ]; then
        pass "$name=read"
      elif [ -z "$write_path" ]; then
        unver "$name=$level: read access confirmed; no side-effect-free write probe"
      else
        unver "$name=$level: read access confirmed; write not probed (--read-only)"
      fi
      ;;
    403) fail "$name=$level: $(explain 403)" ;;
    *) unver "$name=$level: inconclusive ($(explain "$probe_status"))" ;;
  esac
}

echo
echo "Declared permissions (${manifest#"$top"/})"
entries="$(sed -e 's/#.*//' -e 's/[[:space:]]//g' -e '/^$/d' "$manifest")"
[ -n "$entries" ] || fail "the manifest lists no permissions"
while IFS= read -r entry <&3; do
  [ -n "$entry" ] || continue
  case "$entry" in
    ?*=?*) probe_permission "${entry%%=*}" "${entry#*=}" ;;
    *) fail "manifest line is not permission=level: $entry" ;;
  esac
done 3<<EOF
$entries
EOF

finish
