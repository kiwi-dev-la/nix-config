# Rules for every repo under ~/dev

- Commit and push on your own. Do not ask first.
- No AI attribution in commits, PRs or any authored content. Sign as your own
  persona: set `AGENT_PERSONA` and your commits carry that name.
- Create and use branches in GitButler (`but`). Never run `git checkout -b`,
  `git switch -c` or `git branch <name>`.
- No worktrees. Never run `git worktree add`.

These are enforced, not advisory. Every dev shell built from this repo puts
`rules/git-guard.sh` in front of git, and it refuses the commands above and any
commit or push carrying AI attribution. `nix flake check` proves each rule.

## GitButler

Branches, commits, pushes and pull requests are made with `but`; the installed
GitButler skill has the commands. Plain git stays for reading: log, blame, diff.

- One GitButler branch per agent session, named `<persona>/<short-description>`
  after your `AGENT_PERSONA`. Commit only that session's changes to it.
- Other agents may be working in the same repository. Never move, amend,
  squash, discard or push their branches unless the user asks.
- Commit at each working checkpoint: the change complete, its checks run.
  Messages follow `type(scope): summary`.
- Fold a small follow-up into the unpublished commit it belongs to rather than
  adding a fixup commit. Split unrelated changes by hunk, and keep tests with
  the behaviour they verify. Ask only before rewriting pushed or shared history.
- Dependent work goes on a stacked branch (`but move`), and its pull request is
  opened with `but pr`, not `gh`, so the stack's bases stay right.
- Push the branch and open its pull request yourself, as a draft until the
  user says it is ready. "ship it" means: commit, push and open or update the
  pull request, without asking again.
- Update from the target branch with `but pull` when only this session's
  branches are applied. With other agents' branches applied, run
  `but pull --check` first and ask before updating if it reports conflicts.
