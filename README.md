# nix-config

nix-darwin + home-manager for Joel's MacBook Pro. No Homebrew. Apps that Nix
cannot supply well are installed from the vendor and listed in
`hosts/hand-installed-apps.nix`.

## Fresh Mac bootstrap

1. Install Determinate Nix: https://determinate.systems (download the macOS installer).
2. `xcode-select --install` (gives macOS git).
3. Clone and switch:

   ```sh
   mkdir -p ~/dev && git clone https://github.com/kiwi-dev-la/nix-config ~/dev/nix-config
   cd ~/dev/nix-config
   sudo nix run nix-darwin/master#darwin-rebuild -- switch --flake .#Joels-MacBook-Pro
   ```

4. Open a new Terminal window. From then on, `rebuild` applies changes.
5. `gh auth login` (choose HTTPS) so git can clone and push your private repos.

Nix only sees files that git knows about. After adding a new file to this
repo, run `git add <file>` before `rebuild`.

## Adding an app when you need it

Find it with `nix search nixpkgs <name>`, add it to `environment.systemPackages`
in `hosts/macbook-pro.nix`, run `rebuild`. Remove the line to uninstall it.

## Layout

- `hosts/macbook-pro.nix`: system: GUI apps, fonts, macOS defaults, Touch ID sudo.
- `home/default.nix`: user: zsh, prompt, CLI tools, git.
- `rules/`: the git guard that enforces `AGENTS.md` in every shell, and its test.
- `forgejo/`: the forge, its runner and the `forge-*` commands.
- `templates/devshell`: per-project environment.

## New project environment

```sh
cd ~/dev/<repo>
nix flake init -t github:kiwi-dev-la/nix-config#devshell
git add flake.nix .envrc
direnv allow
```

Tools listed in the repo's `flake.nix` load when you `cd` in and unload when you leave.

## The forge (Forgejo)

A local Forgejo server, its Actions runner and the `fj` CLI, all declared in
`forgejo/default.nix`: port, org, runner labels, the repos to seed. Nothing is
set up by hand.

```sh
nix develop ~/dev/nix-config#forgejo
forge-up            # terminal 1: the server, http://127.0.0.1:3600
forge-bootstrap     # once it is up: admin, token, org, runner registration
forge-runner-up     # terminal 2: the runner; a workflow asks for `runs-on: macos`
forge-seed          # copy the fleet's repos from GitHub (uses `gh auth token`)
forge-status        # health check; exits non-zero when anything is missing
```

State lives in `~/.local/state/forgejo` (override with `FORGE_HOME`). Secrets
are generated there on first start and are never in this repo or the Nix
store. Every command can be run again; each only adds what is missing.

nixpkgs marks Forgejo broken on macOS and caches no binary for it, so the
first `nix develop` compiles it from source with its test phase off. One
upstream test fails on macOS (`TestGrepSearch`, the code-search path).
