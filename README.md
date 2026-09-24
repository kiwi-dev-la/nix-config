# nix-config

Personal [nix-darwin](https://github.com/nix-darwin/nix-darwin) +
[home-manager](https://github.com/nix-community/home-manager) config for
Joel Schaeffer’s Mac. First repo on
[kiwi-dev-la](https://github.com/kiwi-dev-la).

This is not a fork of Mitchell Hashimoto’s `nixos-config`. That tree is a
textbook. This tree is the print for this machine.

## Nix vs Gruntwork boilerplate

They stack; they do not replace each other.

- **[gruntwork-io/boilerplate](https://github.com/gruntwork-io/boilerplate)**
  renders templates into files. Lightwave already uses it via `lw scaffold`
  for *new* artifacts (a component, a service, a repo skeleton). You run it
  once. It does not keep a Mac in a known state.
- **Nix / nix-darwin** *is* the known state. `darwin-rebuild switch`
  builds this flake and activates it. `gopls`, `nil`, GOPATH, PATH — if
  they live here, they do not depend on a GUI `PATH` or a mise shim.

Use boilerplate if we later want a template that stamps *this* flake shape
for a second machine. Do not run boilerplate on every rebuild. Nix does
not need a Go CLI to apply.

## Apply (when you are ready)

Determinate Nix is already on this Mac and stays in charge of the daemon
and `/etc/nix/nix.conf` (`nix.enable = false`). nix-darwin has never been
activated here; the first switch creates generation 1. Do not run it until
you have read `hosts/macbook-pro.nix` and `home/default.nix`. `flake.lock`
is the pin: do not `nix flake update` as part of applying.

Everything below was verified on 2026-09-24 by building this flake's
system closure and reading its activation script, not from documentation.

### 1. Move aside the one file nix-darwin does not recognise

nix-darwin refuses to overwrite any `/etc` file whose content is not in its
known-hash list. The Determinate installer's `/etc/nix/nix.custom.conf` is
not, so activation stops (harmlessly, before writing anything) until it is
renamed:

```bash
sudo mv /etc/nix/nix.custom.conf /etc/nix/nix.custom.conf.before-nix-darwin
```

`/etc/zshenv`, `/etc/zshrc`, `/etc/bashrc` and `/etc/zprofile` as the
installer left them are recognised and get the same `.before-nix-darwin`
rename automatically. `/etc/shells` is not managed by this configuration
(no `environment.shells` is set) and is left alone. After the switch the
Determinate module owns `nix.custom.conf`; extra Nix settings go in the
flake, not in that file. `/run` does not exist on this Mac yet; activation
creates it itself (a `run` line in `/etc/synthetic.conf` plus
`apfs.util -t`).

### 2. Build first, activate second

Building writes only to the Nix store:

```bash
nix build .#darwinConfigurations.Joels-MacBook-Pro.system
```

Activation must run as root. `darwin-rebuild` is not installed until the
first switch; the build above put one inside `result`, at exactly the
version `flake.lock` pins, so bootstrap from there:

```bash
sudo ./result/sw/bin/darwin-rebuild switch --flake .#Joels-MacBook-Pro
```

Afterwards `sudo darwin-rebuild switch --flake .` is enough. The attribute
name equals this machine's LocalHostName, so a switch on the wrong machine
finds no configuration instead of applying this one.

### 3. What generation 1 changes

Beyond the files above: `/etc/static`, `/run/current-system`, the
`org.nixos.activate-system` LaunchDaemon (runs once when loaded and again
at every boot), an empty `/Applications/Nix Apps`,
`/etc/profiles/per-user/joelschaeffer` (git, nil, nixfmt, direnv, man-db,
and an `hm-session-vars.sh` carrying GOPATH, GOBIN and GOMODCACHE at their
current values), and the macOS HostName (LocalHostName already matches).
In the home directory it creates `~/.config/git/config` and
`~/.config/direnv/lib/hm-nix-direnv.sh` as store symlinks, `.keep` markers
in `~/.cache` and `~/.local/state`, a gc-root under
`~/.local/state/home-manager`, and the empty `~/Applications/Home Manager
Apps` and `~/Library/Fonts/HomeManager`. `~/.gitconfig` stays and wins over
`~/.config/git/config` on any key both set. It declares no launchd agents,
creates no user, leaves the login shell at `/bin/zsh`, and touches no
existing dotfile.

The one behavioural change to plan for: nix-darwin's `/etc/zshenv` sets
PATH outright (it does not prepend) in every zsh where
`__NIX_DARWIN_SET_ENVIRONMENT_DONE` is unset. `~/.zprofile` re-adds
Homebrew and `~/.local/bin`; mise shims, `~/.bun/bin` and `~/go/bin` only
return through `~/.zshrc`, so non-interactive shells never get them back.
The generated `/etc/zprofile` also drops Apple's `path_helper`, so login
shells lose the `/etc/paths.d` entries (cryptex tools,
`/Library/Apple/usr/bin`, BaselightLOOK). Shells already open at switch
time, any launchd job that runs `/bin/zsh`, and any `bash -l` or `sh -l`
job see the replaced PATH; non-login bash and sh jobs do not. Today that
reaches `com.lightwave.ledger.collect-github` (`zsh -lc`, needs `bun`, will
fail) and `com.lightwave.validity-runaway-report` (`zsh -c`, absolute
paths, survives). Convert zsh-based jobs to bash or absolute paths before
switching.

### 4. Going back

Generation 1 has no earlier generation to roll back to. `darwin-uninstaller`
activates an empty system that removes every `/etc` symlink into
`/etc/static`, unloads and deletes the `org.nixos.activate-system` daemon,
and renames every `*.before-nix-darwin` under `/etc` back into place,
`nix.custom.conf` included. It then removes `/run/current-system` and the
`run` line from `/etc/synthetic.conf` (`/run` itself goes at the next
reboot). Leftovers to clean by hand: an empty `/etc/determinate/` and a
stray `/etc/synthetic.conf-E` backup from BSD `sed`. Determinate Nix keeps
working throughout: with `nix.enable = false` nix-darwin ships no
`/etc/nix/nix.conf` and no `org.nixos.nix-daemon`, and never touches
`systems.determinate.nix-daemon`.

## Layout

```
flake.nix           inputs + darwinConfigurations
hosts/macbook-pro.nix   nix-darwin (the Mac)
home/default.nix        home-manager (the user)
```
