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
