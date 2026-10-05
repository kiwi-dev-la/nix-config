{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  # Carries the environment rules (AGENTS.md there) into this project's shell.
  inputs.nix-config.url = "github:kiwi-dev-la/nix-config";
  inputs.nix-config.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { nixpkgs, nix-config, ... }:
    let
      forEachSystem = f: nixpkgs.lib.genAttrs [ "aarch64-darwin" "x86_64-linux" ]
        (system: f nixpkgs.legacyPackages.${system});
    in {
      devShells = forEachSystem (pkgs: {
        default = pkgs.mkShell {
          packages = [
            # Keep first: this git refuses worktrees, branch creation and AI attribution.
            nix-config.packages.${pkgs.stdenv.hostPlatform.system}.git-guard
          ] ++ (with pkgs; [
            # This project's tools, e.g. nodejs_22 bun python313 go zig terraform
          ]);
        };
      });
    };
}
