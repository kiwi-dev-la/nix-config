{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { nixpkgs, ... }:
    let
      forEachSystem = f: nixpkgs.lib.genAttrs [ "aarch64-darwin" "x86_64-linux" ]
        (system: f nixpkgs.legacyPackages.${system});
    in {
      devShells = forEachSystem (pkgs: {
        default = pkgs.mkShell {
          # This project's tools, e.g. nodejs_22 bun python313 go zig terraform
          packages = with pkgs; [ ];
        };
      });
    };
}
