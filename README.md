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

## The factory (NixOS in a VM)

macOS stays the host for GUI apps. Dev work and every always-on service run in
a NixOS virtual machine, defined in `machines/factory` and run by QEMU. It needs
only Nix on the Mac: no sudo, no Linux builder, no account.

```sh
nix run github:kiwi-dev-la/nix-config#factory-vm -- up   # create it, or start it
nix run github:kiwi-dev-la/nix-config#factory-prove      # use it for real; fails if anything is broken
```

`up` on a Mac with no VM takes about four minutes: it boots a pinned Debian
image, replaces it with NixOS built from this flake inside the VM, and reboots.
The VM's disk lives in `~/.local/state/factory-vm`; its SSH key is
`~/.ssh/factory_ed25519`, created on first use and never stored here.

| Command | What it does |
|---|---|
| `factory-vm up` | Create the VM if there is none, start it if it is stopped |
| `factory-vm status` | Running or not, and any failed services |
| `factory-vm ssh [command]` | A shell (or one command) in the VM |
| `factory-vm switch [flake]` | Apply a configuration: this checkout's by default, or e.g. `github:kiwi-dev-la/nix-config` |
| `factory-vm stop` | Shut it down |
| `factory-vm destroy --yes` | Delete the VM and its disk |

In the VM, at the same address from the Mac and from inside:

- Forgejo, the local forge: http://127.0.0.1:3300. Log in as `joel`; the
  password is generated on first boot: `factory-vm ssh sudo cat /var/lib/forgejo/admin-password`.
- A Forgejo Actions runner. A workflow job with `runs-on: native` runs on the
  VM itself with Nix available.

`factory-prove` creates a repository, pushes to it from the Mac, clones it
back, opens an issue, opens and merges a pull request that closes the issue,
waits for the build the merge starts, and checks Forgejo logged no errors.

## Layout

- `machines/factory/`: the NixOS VM: base system, disk, Forgejo and its runner.
- `vm/`: the `factory-vm` and `factory-prove` commands.
- `hosts/macbook-pro.nix`: system: GUI apps, fonts, macOS defaults, Touch ID sudo.
- `home/default.nix`: user: zsh, prompt, CLI tools, git.
- `rules/`: the git guard that enforces `AGENTS.md` in every shell, and its test.
- `forgejo/`: the forge's declaration and the `forge-*` commands that drive it.
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

One Forgejo forge, served by the factory VM and declared in
`forgejo/declaration.nix`: port, org, admin, runner labels, the repos to seed.
The `forge-*` commands bring it to the declared state from the Mac. Nothing is
set up by hand.

```sh
nix develop ~/dev/nix-config#forgejo
nix run ~/dev/nix-config#factory-vm -- ssh sudo cat /var/lib/forgejo/admin-password | forge-bootstrap
forge-seed          # copy the fleet's repos from GitHub (uses `gh auth token`)
forge-workflows     # put the fleet's CI workflow in every repo
forge-status        # health check; exits non-zero when anything is missing
```

`forge-bootstrap` makes this Mac's API token, the org and this Mac's runner
registration. It reads the admin password only when the Mac holds no token the
forge accepts; after that, run it bare.

Every repo carries the same workflow, `.forgejo/workflows/ci.yml`, stamped
from `forgejo/workflow.yml`. It has one job with one step, `forge-ci`, a
command each runner puts on its jobs' PATH. `forge-ci` checks the commit out
and runs the repo's gate, `mise run ci`, on a push to main and on every pull
request. The result is the commit status `ci / ci (push)` or
`ci / ci (pull_request)`. `ci.runsOn` in the declaration names the runner for
the whole fleet. `forge-status` fails while any repo's copy differs.

The gate runs in the environment the repo declares: its flake's `ci` dev
shell, else its `default` one. A repo with no flake gets the tools its
`mise.toml` installs and whatever the runner's host has, so a gate that leans
on a tool the repo does not declare fails here even if it passes at your desk.

To run a repo's gate again without a commit:

```sh
curl --header @~/.local/state/forgejo/secrets/admin_auth_header --json '{"ref": "main"}' \
  http://127.0.0.1:3300/api/v1/repos/lightwave-media/<repo>/actions/workflows/ci.yml/dispatches
```

The stamp is a commit in the forge only, not on GitHub. A repo seeded again
from GitHub needs `forge-workflows` again.

Two runners take jobs. The VM's own runs `runs-on: native` on Linux with Nix.
The Mac's runs `runs-on: macos` on the Mac itself, as you.

The Mac's runner is a login service, declared in `forgejo/runner-agent.nix`.
launchd starts it once `forge-bootstrap` has registered it, it waits for the
forge when the VM is not up yet, and launchd restarts it if it stops. Its log
is `~/Library/Logs/forge-runner.log`. `forge-runner-up` runs the same runner
in the foreground.

A rebuilt VM is a new forge that knows neither this Mac's token nor its
runner. Run `forge-bootstrap` with the password again; the runner picks up
the new registration within 30 seconds.

The Mac's token and runner registration live in `~/.local/state/forgejo`
(override with `FORGE_HOME`), never in this repo or the Nix store. Every
command can be run again; each only adds what is missing. `FORGE_URL` points
every command at a forge on another address.
