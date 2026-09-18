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

Determinate Nix is already on this Mac. From a clone:

```bash
nix flake update
darwin-rebuild switch --flake .#Joels-MacBook-Pro
```

Do not run that until you have read `hosts/macbook-pro.nix`. The first
switch will take over nix-darwin-managed settings.

## Layout

```
flake.nix           inputs + darwinConfigurations
hosts/macbook-pro.nix   nix-darwin (the Mac)
home/default.nix        home-manager (the user)
```
