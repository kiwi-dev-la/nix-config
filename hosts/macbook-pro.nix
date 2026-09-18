{ pkgs, ... }:

{
  nixpkgs.hostPlatform = "aarch64-darwin";
  nixpkgs.config.allowUnfree = true;

  # Determinate Nix owns /etc/nix. Do not let nix-darwin fight it.
  nix.enable = false;

  networking.hostName = "Joels-MacBook-Pro";

  users.users.joelschaeffer = {
    home = "/Users/joelschaeffer";
    shell = pkgs.zsh;
  };

  system.primaryUser = "joelschaeffer";

  # Used by nix-darwin for backwards-compatible defaults. Bump only when
  # the nix-darwin release notes say to.
  system.stateVersion = 6;

  environment.systemPackages = with pkgs; [
    git
    nil
    nixfmt
  ];

  programs.zsh.enable = true;

  environment.variables = {
    GOPATH = "/Users/joelschaeffer/.local/share/go";
    GOMODCACHE = "/Users/joelschaeffer/Library/Caches/go-mod";
    GOBIN = "/Users/joelschaeffer/.local/bin";
  };
}
