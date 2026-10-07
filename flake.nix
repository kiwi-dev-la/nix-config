{
  description = "Joel's Mac: nix-darwin + home-manager, Nix for everything";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    # The factory's definition (NixOS module, programs, scripts). A private
    # repository, read over SSH with this Mac's key; `factory-vm switch` ships
    # it to the VM with the rest of the inputs, so the VM never logs in
    # anywhere. Pinned to a commit; moved by the rule for program changes.
    lightwave-ai.url = "git+ssh://git@github.com/lightwave-media/lightwave-ai?ref=refs/tags/factory-step5d";
  };

  outputs = { self, nixpkgs, nix-darwin, home-manager, disko, lightwave-ai, ... }:
    let
      inherit (nixpkgs) lib;
      forEachSystem = f: lib.genAttrs [ "aarch64-darwin" "aarch64-linux" "x86_64-linux" ]
        (system: f nixpkgs.legacyPackages.${system});

      gitGuard = pkgs: import ./rules/git-guard.nix { inherit pkgs lib; };
      forge = pkgs: import ./forgejo { inherit pkgs lib; gitGuard = gitGuard pkgs; };
    in
    {
      darwinConfigurations."Joels-MacBook-Pro" = nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        modules = [
          ./hosts/macbook-pro.nix
          ./hosts/hand-installed-apps.nix
          ./forgejo/runner-agent.nix
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "hm-backup";
            home-manager.extraSpecialArgs = { inherit lightwave-ai; nixConfig = self; };
            home-manager.users.joelschaeffer = import ./home;
          }
        ];
      };

      # The factory: NixOS in a VM on the Mac. `nix run .#factory-vm -- up`
      nixosConfigurations.factory = lib.nixosSystem {
        system = "aarch64-linux";
        specialArgs = { inherit lightwave-ai; };
        modules = [ disko.nixosModules.disko ./machines/factory ];
      };

      packages = forEachSystem (pkgs: {
        git-guard = gitGuard pkgs;
      } // (forge pkgs).packages
        // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin
        (import ./vm { inherit pkgs; flake = self; }));

      # The gate the forge's runner runs (forge-ci): the rules' proofs, and both
      # machines' configurations evaluate. The Mac's is built only by a Mac runner.
      apps = forEachSystem (pkgs: {
        ci = {
          type = "app";
          program = lib.getExe (pkgs.writeShellApplication {
            name = "nix-config-ci";
            runtimeInputs = [ pkgs.nix pkgs.git ];
            text = ''
              cd "$(git rev-parse --show-toplevel)"
              echo "▶ nix flake check"
              nix flake check
              ${lib.concatMapStrings (name: ''
                echo "▶ build packages.${pkgs.stdenv.hostPlatform.system}.${name}"
                nix build --no-link ".#packages.${pkgs.stdenv.hostPlatform.system}.${name}"
              '') (builtins.attrNames self.packages.${pkgs.stdenv.hostPlatform.system})}
              echo "▶ the Mac's configuration evaluates"
              nix eval --raw .#darwinConfigurations.Joels-MacBook-Pro.system.drvPath >/dev/null
              echo "▶ the factory's configuration evaluates"
              nix eval --raw .#nixosConfigurations.factory.config.system.build.toplevel.drvPath >/dev/null
            '';
          });
        };
      });

      # `nix develop ~/dev/nix-config#forgejo`: the forge's commands and this host's runner.
      devShells = forEachSystem (pkgs: {
        forgejo = (forge pkgs).shell;

        # `nix develop .#default`: what factory workers get in this repository.
        default = pkgs.mkShell {
          inputsFrom = [ (forge pkgs).shell ];
          packages = [
            (gitGuard pkgs)
            pkgs.git
            pkgs.jq
            pkgs.curl
            pkgs.shellcheck
            pkgs.nixfmt
          ];
        };
      });

      # `nix flake check` proves each rule against a scratch repository.
      checks = forEachSystem (pkgs: {
        git-guard = pkgs.runCommand "git-guard-test"
          { nativeBuildInputs = [ (gitGuard pkgs) ]; }
          ''
            bash ${./rules/git-guard-test.sh}
            touch "$out"
          '';
      });

      # Per-project dev environment: `nix flake init -t github:kiwi-dev-la/nix-config#devshell`
      templates.devshell = {
        path = ./templates/devshell;
        description = "Project flake with a devShell, loaded by direnv on cd";
      };
    };
}
