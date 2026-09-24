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
    lightwave-cli.url = "github:lightwave-media/lightwave-cli/v3.16.0";
    lightwave-cli.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, nix-darwin, home-manager, determinate, lightwave-cli, ... }: {
    # `nix build .#lw` builds exactly the lw this host pins; lw:sync targets it.
    packages.aarch64-darwin.lw = lightwave-cli.packages.aarch64-darwin.lw;

    darwinConfigurations."Joels-MacBook-Pro" = nix-darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      modules = [
        determinate.darwinModules.default
        ./hosts/macbook-pro.nix
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
