{
  description = "Joel's Mac: nix-darwin + home-manager, Nix for everything";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, nix-darwin, home-manager, ... }: {
    darwinConfigurations."Joels-MacBook-Pro" = nix-darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      modules = [
        ./hosts/macbook-pro.nix
        ./hosts/hand-installed-apps.nix
        home-manager.darwinModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "hm-backup";
          home-manager.users.joelschaeffer = import ./home;
        }
      ];
    };

    # Per-project dev environment: `nix flake init -t github:kiwi-dev-la/nix-config#devshell`
    templates.devshell = {
      path = ./templates/devshell;
      description = "Project flake with a devShell, loaded by direnv on cd";
    };
  };
}
