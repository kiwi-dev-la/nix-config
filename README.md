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

One Forgejo forge, declared in `forgejo/declaration.nix`: port, org, admin,
runner labels, the repos to seed. The `forge-*` commands bring the Forgejo at
that address to the declared state, whichever host serves it. Nothing is set
up by hand.

```sh
nix develop ~/dev/nix-config#forgejo
forge-up            # terminal 1: serve the forge from this host
forge-bootstrap     # once it is up: this host's API token, the org, this host's runner
forge-runner-up     # terminal 2: this host's runner; on a Mac a workflow asks for `runs-on: macos`
forge-seed          # copy the fleet's repos from GitHub (uses `gh auth token`)
forge-status        # health check; exits non-zero when anything is missing
```

When another host serves the forge, such as a VM, skip `forge-up` and give
`forge-bootstrap` one of that forge's admins. This host still adds its runner,
so macOS jobs have somewhere to run:

```sh
FORGE_ADMIN=<name> FORGE_ADMIN_PASSWORD_FILE=<file> forge-bootstrap
```

`FORGE_URL` points every command at a forge on another address.

State lives in `~/.local/state/forgejo` (override with `FORGE_HOME`). Secrets
are generated there and are never in this repo or the Nix store. Every command
can be run again; each only adds what is missing.

nixpkgs marks Forgejo broken on macOS and caches no binary for it, so the
first `nix develop` on a Mac compiles it from source with its test phase off. One
upstream test fails on macOS (`TestGrepSearch`, the code-search path).
