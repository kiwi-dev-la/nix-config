{
  description = "Joel Schaeffer's nix-darwin configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # Keeps nix-darwin from overwriting Determinate's /etc/nix.
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/3";

    # The released lw CLI, pinned by tag. `mise run lw:sync` (the one lw
    # installer) builds this and links the binary into ~/.local/bin.
    # Deliberately NOT in home.packages: two copies of lw on PATH, with a
    # different winner per shell type, is the drift this repo exists to
    # remove. Roll lw forward by bumping the tag and re-locking.
    lightwave-cli.url = "github:lightwave-media/lightwave-cli/v3.17.1";
    lightwave-cli.inputs.nixpkgs.follows = "nixpkgs";

    # The released lightwave-core schema library, pinned by tag, so a check
    # can read a released schema surface instead of whatever branch the ~/dev
    # checkout has out. Per core's own flake: pass it PER INVOCATION
    # (LW_LIGHTWAVE_ROOT=$(nix build --print-out-paths .#schemas) lw check
    # schema) and never export it session-wide; lw resolves sibling repos from
    # that root, and this tree carries no runbooks or boilerplate. The repo is
    # private, so this is git+ssh (a github: ref 404s without a token). Roll
    # forward by bumping the tag and re-locking, same as lightwave-cli.
    lightwave-core.url = "git+ssh://git@github.com/lightwave-media/lightwave-core?ref=refs/tags/v0.9.1";
    lightwave-core.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, nix-darwin, home-manager, determinate, lightwave-cli, lightwave-core, ... }: {
    # `nix build .#lw` builds exactly the lw this host pins; lw:sync targets it.
    packages.aarch64-darwin.lw = lightwave-cli.packages.aarch64-darwin.lw;
    # `nix build .#schemas` is the pinned schema tree; per-invocation only.
    packages.aarch64-darwin.schemas = lightwave-core.packages.aarch64-darwin.schemas;

    # Retires a hand-written launchd job only after its nix-darwin replacement
    # is installed and has run. Dry run unless given --apply.
    apps.aarch64-darwin.archive-launchd = {
      type = "app";
      program = "${nixpkgs.legacyPackages.aarch64-darwin.writeShellApplication {
        name = "archive-launchd";
        runtimeInputs = [ nixpkgs.legacyPackages.aarch64-darwin.coreutils ];
        text = builtins.readFile ./scripts/archive-launchd.sh;
      }}/bin/archive-launchd";
    };

    darwinConfigurations."Joels-MacBook-Pro" = nix-darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      # The pinned lw, for launchd jobs that inject secrets with `lw config exec`.
      specialArgs.lw = lightwave-cli.packages.aarch64-darwin.lw;
      modules = [
        determinate.darwinModules.default
        ./hosts/macbook-pro.nix
        ./hosts/launchd-agents.nix
        home-manager.darwinModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.joelschaeffer = import ./home;
        }
      ];
    };
  };
}
