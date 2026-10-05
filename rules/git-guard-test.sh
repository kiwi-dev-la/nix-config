# Proves rules/git-guard.sh against a scratch repository. Run by `nix flake check`
# with the guarded git first on PATH.
set -euo pipefail

work="$(mktemp -d)"
export HOME="$work/home"
mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_EMAIL=test@example.invalid GIT_COMMITTER_EMAIL=test@example.invalid
cd "$work"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# The guard exits 2 when a rule blocks the command.
blocked() {
  local rc=0
  "$@" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 2 ] || fail "expected a block (exit 2), got $rc: $*"
}

allowed() {
  "$@" >/dev/null 2>&1 || fail "expected this to run: $*"
}

git init -q -b main repo
git init -q --bare remote.git
cd repo
git config user.name tester
git remote add origin "$work/remote.git"
allowed git commit --allow-empty -m "first"
allowed git push -u origin main

# 1. No worktrees.
blocked git worktree add ../wt
blocked git worktree move a b
allowed git worktree list
allowed git worktree prune

# 2. No branch creation with git.
blocked git checkout -b feature
blocked git checkout -B feature
blocked git checkout --orphan feature
blocked git switch -c feature
blocked git switch --create feature
blocked git branch feature
blocked git branch -c main feature
blocked git -C . branch feature
allowed git branch --show-current
allowed git branch --list
allowed git branch -vv
allowed git checkout main
allowed git switch main
[ "$(git branch --list | wc -l | tr -d ' ')" = 1 ] || fail "a branch was created"

# 3. No AI attribution: refused in the message, and refused at the push.
blocked git commit --allow-empty -m "change" -m "Co-Authored-By: Claude <noreply@anthropic.com>"
blocked git commit --allow-empty -m "change

Generated with [Claude Code](https://claude.com/claude-code)"
printf 'change\n\nCo-authored-by: Codex <codex@openai.com>\n' >"$work/msg"
allowed git commit --allow-empty -F "$work/msg"
blocked git push origin main
allowed git commit --amend --allow-empty -m "change"
allowed git push origin main

# A human co-author is not AI attribution.
allowed git commit --allow-empty -m "pair" -m "Co-Authored-By: Ada Lovelace <ada@example.invalid>"
allowed git push origin main

# 4. No secrets pushed. The token is made here so this file never holds one.
secret="ghp_"
while [ "${#secret}" -lt 40 ]; do secret+="$(printf '%x' "$RANDOM")"; done
printf 'token = "%s"\n' "${secret:0:40}" >config.txt
git add config.txt
allowed git commit -m "add config"
blocked git push origin main
(cd "$work" && blocked git -C repo push origin main)
# GitButler pushes from inside the git directory: the scan must still run there.
(cd .git && blocked git push origin main)
git rm -q --cached config.txt
rm config.txt
allowed git commit --amend --allow-empty -m "add nothing"
(cd .git && allowed git push origin main)

# An agent commits as its persona.
AGENT_PERSONA=v_test git commit -q --allow-empty -m "as persona"
[ "$(git log -1 --format=%an)" = v_test ] || fail "commit was not authored by the persona"
[ "$(git log -2 --format=%an | tail -1)" = tester ] || fail "persona leaked into a commit made without one"

echo "git-guard: every rule holds"
