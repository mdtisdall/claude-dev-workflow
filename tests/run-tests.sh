#!/usr/bin/env bash
# Tests for the plugin's shell scripts. They use local git fixtures and a fake
# gh, with no network. They run under macOS /bin/bash 3.2.
#
#   bash tests/run-tests.sh
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/dev-workflow-tests.XXXXXX")"
tmp="$(cd "$tmp" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT

# `bash` and `#!/usr/bin/env bash` find this link first, so each script runs
# under the bash that runs the tests: `/bin/bash tests/run-tests.sh` tests all
# of them with macOS bash 3.2.
mkdir "$tmp/bash-bin"
ln -s "$BASH" "$tmp/bash-bin/bash"
printf 'bash %s (%s)\n' "$BASH_VERSION" "$BASH"

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
export PATH="$tmp/bash-bin:$root/tests/fake-bin:$PATH"
export DEV_WORKFLOW_SKIP_DIRENV=1
unset GH_TOKEN FAKE_GH_RULES FAKE_GH_PR_JSON FAKE_GH_LOG DEV_WORKFLOW_HOOK_NO_JQ

passed=0
failed=0
LAST_OUT=""

section() { printf '\n# %s\n' "$1"; }
ok() {
  passed=$((passed + 1))
  printf 'ok    %s\n' "$1"
}
not_ok() {
  failed=$((failed + 1))
  printf 'FAIL  %s\n' "$1"
  [ -z "${2:-}" ] || printf '%s\n' "$2" | sed 's/^/      | /'
}
# expect_exit NAME CODE COMMAND...
expect_exit() {
  local name="$1" want="$2" got
  shift 2
  LAST_OUT="$("$@" 2>&1)"
  got=$?
  if [ "$got" = "$want" ]; then ok "$name"; else not_ok "$name (exit $got, expected $want)" "$LAST_OUT"; fi
}
# expect_out NAME TEXT: the output of the last expect_exit contains TEXT.
expect_out() {
  case "$LAST_OUT" in
    *"$2"*) ok "$1" ;;
    *) not_ok "$1 (output does not contain: $2)" "$LAST_OUT" ;;
  esac
}
expect_true() {
  local name="$1"
  shift
  if "$@"; then ok "$name"; else not_ok "$name"; fi
}
in_dir() {
  local d="$1"
  shift
  (cd "$d" && "$@")
}
quiet() { "$@" >/dev/null 2>&1; }

# make_repo NAME: $tmp/NAME (main pushed) with the bare origin $tmp/NAME-origin.git.
make_repo() {
  local d="$tmp/$1"
  quiet git init --bare -b main "$d-origin.git"
  quiet git init -b main "$d"
  printf '.envrc.local\n.envrc.local.*\n' >"$d/.gitignore"
  echo readme >"$d/README.md"
  git -C "$d" add .gitignore README.md
  quiet git -C "$d" commit -m init
  git -C "$d" remote add origin "$d-origin.git"
  quiet git -C "$d" push -u origin main
  quiet git -C "$d" remote set-head origin main
}

mode_of() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"; }

# -----------------------------------------------------------------------------
section "test environment"

expect_true "scripts run under the bash that runs the tests" \
  bash -c '[ "$BASH_VERSION" = "$1" ]' _ "$BASH_VERSION"

# -----------------------------------------------------------------------------
section "block-main-writes.sh (hook)"

hook="$root/skills/project-setup/templates/block-main-writes.sh"
make_repo hook
M="$tmp/hook"
F="$tmp/hook-x"
quiet git -C "$M" worktree add -b feature/x "$F" origin/main

run_hook() {
  jq -cn --arg c "$1" --arg d "$2" \
    '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: $c}, cwd: $d}' \
    | CLAUDE_PROJECT_DIR="$M" bash "$hook"
}

for mode in jq no-jq; do
  if [ "$mode" = no-jq ]; then export DEV_WORKFLOW_HOOK_NO_JQ=1; fi
  expect_exit "[$mode] commit on main: blocked" 2 run_hook 'git commit -m x' "$M"
  expect_out "[$mode] the block message names the branch" 'on `main`'
  expect_exit "[$mode] commit on a feature branch: allowed" 0 run_hook 'git commit -m x' "$F"
  expect_exit "[$mode] commit with an escaped-quote message on main: blocked" 2 run_hook 'git commit -m "fix: \"quoted\""' "$M"
  expect_exit "[$mode] commit with an escaped-quote message on a branch: allowed" 0 run_hook 'git commit -m "fix: \"quoted\""' "$F"
  expect_exit "[$mode] cd into a branch worktree, then commit: allowed" 0 run_hook "cd $F && git commit -m x" "$M"
  expect_exit "[$mode] git -C <main checkout> commit: blocked" 2 run_hook "git -C $M commit -m x" "$F"
  expect_exit "[$mode] git -c option before commit on main: blocked" 2 run_hook 'git -c core.hooksPath=/dev/null commit -m x' "$M"
  expect_exit "[$mode] push of a feature branch: allowed" 0 run_hook 'git push -u origin feature/x' "$F"
  expect_exit "[$mode] push HEAD:main from a branch: blocked" 2 run_hook 'git push origin HEAD:main' "$F"
  expect_exit "[$mode] push main from a branch: blocked" 2 run_hook 'git push origin main' "$F"
  expect_exit "[$mode] push --all from a branch: blocked" 2 run_hook 'git push --all origin' "$F"
  expect_exit "[$mode] bare push on main: blocked" 2 run_hook 'git push' "$M"
  expect_exit "[$mode] push origin on main: blocked" 2 run_hook 'git push origin' "$M"
  expect_exit "[$mode] delete a feature branch from main: allowed" 0 run_hook 'git push origin --delete feature/x' "$M"
  expect_exit "[$mode] delete main from a branch: blocked" 2 run_hook 'git push origin --delete main' "$F"
  expect_exit "[$mode] push a branch, then a separate command that mentions main: allowed" 0 run_hook 'git push -u origin feature/x && git log main' "$F"
  expect_exit "[$mode] push a branch, then commit on main: blocked" 2 run_hook 'git push origin feature/x; git commit -m y' "$M"
  expect_exit "[$mode] git log on main: allowed" 0 run_hook 'git log --oneline -5' "$M"
  expect_exit "[$mode] a command that is not git: allowed" 0 run_hook 'ls -la' "$M"
done
unset DEV_WORKFLOW_HOOK_NO_JQ

# -----------------------------------------------------------------------------
section "new-worktree.sh"

nw="$root/skills/start-task/scripts/new-worktree.sh"
make_repo wt
W="$tmp/wt"
printf 'export GH_TOKEN="github_pat_x"\n' >"$W/.envrc.local"

expect_exit "rejects a branch with no type" 1 in_dir "$W" bash "$nw" add-thing
expect_exit "rejects an unknown type" 1 in_dir "$W" bash "$nw" feat/add-thing
expect_exit "creates a worktree" 0 in_dir "$W" bash "$nw" feature/add-thing
expect_true "the worktree is next to the main checkout" test -d "$tmp/wt-add-thing"
expect_true "the branch is checked out" \
  bash -c "[ \"\$(git -C '$tmp/wt-add-thing' rev-parse --abbrev-ref HEAD)\" = feature/add-thing ]"
expect_true "the branch has no upstream yet" \
  bash -c "! git -C '$tmp/wt-add-thing' rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1"
expect_true ".envrc.local is a link to the main checkout's file" \
  bash -c "[ -L '$tmp/wt-add-thing/.envrc.local' ] && [ \"\$(readlink '$tmp/wt-add-thing/.envrc.local')\" = '$W/.envrc.local' ]"
expect_exit "from a worktree, creates a worktree" 0 in_dir "$tmp/wt-add-thing" bash "$nw" fix/other-thing
expect_true "that worktree is also next to the main checkout" test -d "$tmp/wt-other-thing"
expect_exit "refuses a branch that exists" 1 in_dir "$W" bash "$nw" feature/add-thing
quiet git -C "$W" push origin "origin/main:refs/heads/chore/remote-only"
expect_exit "refuses a branch that exists only on origin" 1 in_dir "$W" bash "$nw" chore/remote-only
expect_out "the refusal names origin" "already exists on origin"
printf 'README.md\n.envrc.local\n' >"$W/.worktree-links"
expect_exit "creates a worktree with .worktree-links" 0 in_dir "$W" bash "$nw" docs/links
expect_out "does not link a tracked path" "not linked (not git-ignored): README.md"
expect_true "the tracked path is not a link" test ! -L "$tmp/wt-links/README.md"
expect_true "the ignored path is a link" test -L "$tmp/wt-links/.envrc.local"

# -----------------------------------------------------------------------------
section "store-gh-token.sh"

st="$root/skills/github-token/scripts/store-gh-token.sh"
make_repo store
S="$tmp/store"
printf 'export OTHER=1\nexport GH_TOKEN="github_pat_old"\n' >"$S/.envrc.local"
store() { in_dir "$1" bash -c "printf '%s\n' '$2' | bash '$st'"; }

expect_exit "rejects a classic token" 1 store "$S" ghp_classic
expect_true "the file is not changed after a rejection" grep -q github_pat_old "$S/.envrc.local"
expect_exit "stores a fine-grained token" 0 store "$S" github_pat_new
expect_true "the output does not contain the token" bash -c "! printf '%s' \"\$1\" | grep -q github_pat_new" _ "$LAST_OUT"
expect_true "replaces the old GH_TOKEN line" \
  bash -c "grep -q 'GH_TOKEN=\"github_pat_new\"' '$S/.envrc.local' && ! grep -q github_pat_old '$S/.envrc.local'"
expect_true "keeps the other lines" grep -q 'OTHER=1' "$S/.envrc.local"
expect_true "writes mode 600" bash -c "[ \"\$1\" = 600 ]" _ "$(mode_of "$S/.envrc.local")"
quiet git -C "$S" worktree add -b feature/s "$tmp/store-wt" origin/main
expect_exit "from a worktree, stores the token" 0 store "$tmp/store-wt" github_pat_fromwt
expect_true "the main checkout's file has the token" grep -q github_pat_fromwt "$S/.envrc.local"
expect_true "no file is written in the worktree" test ! -e "$tmp/store-wt/.envrc.local"
make_repo store2
: >"$tmp/store2/.gitignore"
expect_exit "refuses when .envrc.local is not git-ignored" 1 store "$tmp/store2" github_pat_new
expect_true "writes nothing when it refuses" test ! -e "$tmp/store2/.envrc.local"

# -----------------------------------------------------------------------------
section "check-gh-token.sh"

chk="$root/skills/github-token/scripts/check-gh-token.sh"
make_repo tok
T="$tmp/tok"
git -C "$T" remote set-url origin git@github.com:acme/widget.git
printf 'use flake\nsource_env_if_exists .envrc.local\n' >"$T/.envrc"
printf 'export GH_TOKEN="github_pat_fake"\n' >"$T/.envrc.local"
chmod 600 "$T/.envrc.local"
mkdir -p "$T/.claude"
printf '# test manifest\nmetadata=read\ncontents=write   # merge\npull_requests=write\nactions=read\nworkflows=write\n' \
  >"$T/.claude/gh-token-permissions"
rules="$tmp/tok-rules.tsv"

default_rules() {
  printf 'GET\trepos/acme/widget\t200\tmetadata=read\tGithub-Authentication-Token-Expiration: 2099-01-01 00:00:00 UTC\n'
  printf 'GET\trepos/acme/widget/commits\t200\tcontents=read\n'
  printf 'POST\trepos/acme/widget/git/refs\t422\tcontents=write\n'
  printf 'GET\trepos/acme/widget/pulls\t200\tpull_requests=read\n'
  printf 'POST\trepos/acme/widget/pulls\t422\tpull_requests=write\n'
  printf 'GET\trepos/acme/widget/actions/runs\t200\tactions=read\n'
}
check_token() {
  in_dir "$T" env GH_TOKEN="${TOKEN:-github_pat_fake}" FAKE_GH_RULES="$rules" bash "$chk" "$@"
}

default_rules >"$rules"
expect_exit "passes when every probe succeeds" 0 check_token
expect_out "reports the expiry" "expires 2099-01-01 00:00:00 UTC ("
expect_out "reports a permission without a probe as unverified" "unverified  workflows=write"
expect_out "passes contents=write" "ok          contents=write"

{
  printf 'POST\trepos/acme/widget/git/refs\t403\tcontents=write\n'
  default_rules
} >"$rules"
expect_exit "fails when a write permission is refused" 1 check_token
expect_out "names the missing permission" "contents=write: permission refused (endpoint needs contents=write)"
expect_exit "--read-only does not send write probes" 0 check_token --read-only
expect_out "--read-only reports the write as not probed" "write not probed (--read-only)"

{
  printf 'GET\trepos/acme/widget\t404\n'
  default_rules
} >"$rules"
expect_exit "fails when the repository is not visible" 1 check_token
expect_out "explains the repository access" "cannot see this repository"

default_rules >"$rules"
TOKEN=ghp_classic expect_exit "fails for a classic token" 1 check_token
expect_out "names the classic token" "classic token"
expect_exit "fails without GH_TOKEN" 1 in_dir "$T" env -u GH_TOKEN FAKE_GH_RULES="$rules" bash "$chk"
expect_out "explains direnv exec" "direnv exec ."
chmod 644 "$T/.envrc.local"
expect_exit "fails when .envrc.local is readable by others" 1 check_token
expect_out "names the mode" "mode 644"
chmod 600 "$T/.envrc.local"
expect_exit "reads the file mode with GNU stat (as in a Nix devShell)" 0 \
  in_dir "$T" env PATH="$root/tests/fake-gnu-bin:$PATH" GH_TOKEN=github_pat_fake FAKE_GH_RULES="$rules" bash "$chk"
expect_out "reports mode 600 with GNU stat" "ok          .envrc.local has mode 600"

# -----------------------------------------------------------------------------
section "token-url.sh"

tu="$root/skills/github-token/scripts/token-url.sh"
expect_exit "prints a pre-filled URL" 0 in_dir "$T" bash "$tu"
expect_out "has the name" "https://github.com/settings/personal-access-tokens/new?name=widget-claude"
expect_out "has the owner" "&target_name=acme"
expect_out "has the default expiry" "&expires_in=90"
expect_out "has a permission from the manifest" "&contents=write"
expect_out "tells the user to limit the repository access" "Only select repositories"
expect_exit "rejects --days out of range" 1 in_dir "$T" bash "$tu" --days 400

# -----------------------------------------------------------------------------
section "ci-status.sh"

ci="$root/skills/ship/scripts/ci-status.sh"
prjson="$tmp/ci-pr.json"
printf '{"number":7,"url":"https://github.com/acme/widget/pull/7","headRefOid":"abc123"}\n' >"$prjson"
runs() { printf '{"workflow_runs":[%s]}\n' "$1" >"$tmp/ci-runs.json"; }
run_json() { printf '{"name":"%s","status":"%s","conclusion":%s,"html_url":"https://x/%s"}' "$1" "$2" "$3" "$4"; }
printf 'GET\trepos/acme/widget/actions/runs\t200\t\t\t%s\n' "$tmp/ci-runs.json" >"$tmp/ci-rules.tsv"
ci_status() {
  in_dir "$T" env GH_TOKEN=github_pat_fake FAKE_GH_RULES="$tmp/ci-rules.tsv" \
    FAKE_GH_PR_JSON="$prjson" FAKE_GH_LOG="$tmp/ci-log" bash "$ci" "$@"
}

runs "$(run_json CI completed '"success"' 1)"
expect_exit "success" 0 ci_status 7
expect_out "reports success" "CI: success"
expect_true "asks for the runs of the PR head commit" grep -q 'head_sha=abc123' "$tmp/ci-log"
runs "$(run_json CI completed '"success"' 2),$(run_json CI completed '"failure"' 1)"
expect_exit "a passing re-run replaces an earlier failure" 0 ci_status 7
runs "$(run_json CI completed '"failure"' 1)"
expect_exit "failure" 1 ci_status 7
expect_out "shows the failed run URL" "https://x/1"
runs "$(run_json CI in_progress null 1)"
expect_exit "in progress" 2 ci_status 7
runs ""
expect_exit "no runs yet" 2 ci_status 7
expect_out "reports no runs" "no runs for this commit yet"

# -----------------------------------------------------------------------------
section "cleanup-merged.sh"

cm="$root/skills/finish-task/scripts/cleanup-merged.sh"
make_repo cl
C="$tmp/cl"
quiet git -C "$C" worktree add -b feature/done "$tmp/cl-done" origin/main
echo change >"$tmp/cl-done/file.txt"
git -C "$tmp/cl-done" add file.txt
quiet git -C "$tmp/cl-done" commit -m change
quiet git -C "$tmp/cl-done" push -u origin feature/done
head="$(git -C "$tmp/cl-done" rev-parse HEAD)"
# The squash merge on "GitHub": a different clone pushes the squashed commit.
quiet git clone -b main "$C-origin.git" "$tmp/cl-gh"
quiet git -C "$tmp/cl-gh" merge --squash origin/feature/done
quiet git -C "$tmp/cl-gh" commit -m "change (#7)"
quiet git -C "$tmp/cl-gh" push origin main
merge="$(git -C "$tmp/cl-gh" rev-parse HEAD)"

pr_json() {
  printf '{"state":"%s","headRefName":"feature/done","headRefOid":"%s","mergeCommit":{"oid":"%s"}}\n' \
    "$1" "$2" "$merge" >"$tmp/cl-pr.json"
}
cleanup() { in_dir "$C" env FAKE_GH_PR_JSON="$tmp/cl-pr.json" bash "$cm" "$@"; }

pr_json OPEN "$head"
expect_exit "refuses a PR that is not merged" 1 cleanup 7
pr_json MERGED "$(git -C "$C" rev-parse main)"
expect_exit "refuses when the local branch is not the PR head" 1 cleanup 7
expect_out "explains the local commits" "commits that are not in the PR"
pr_json MERGED "$head"
touch "$tmp/cl-done/stray.txt"
expect_exit "refuses a worktree with an untracked file" 1 cleanup 7
expect_out "names the untracked file" "stray.txt"
rm "$tmp/cl-done/stray.txt"
expect_exit "dry run" 0 cleanup 7 --dry-run
expect_out "verifies the merge contents" "verified: each file"
expect_out "dry run changes nothing" "dry run: nothing changed"
expect_true "dry run keeps the worktree" test -d "$tmp/cl-done"
expect_exit "cleanup" 0 cleanup 7
expect_true "the worktree is removed" test ! -e "$tmp/cl-done"
expect_true "the local branch is deleted" \
  bash -c "! git -C '$C' show-ref --verify --quiet refs/heads/feature/done"
expect_true "the remote branch is deleted" \
  bash -c "[ -z \"\$(git -C '$C' ls-remote --heads origin feature/done)\" ]"
expect_true "main is fast-forwarded to the merge commit" \
  bash -c "[ \"\$(git -C '$C' rev-parse main)\" = '$merge' ]"

# -----------------------------------------------------------------------------
printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
