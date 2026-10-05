{ pkgs, ... }:

{
  # Determinate Nix manages the Nix install itself; nix-darwin must not.
  nix.enable = false;

  nixpkgs.hostPlatform = "aarch64-darwin";
  nixpkgs.config.allowUnfree = true;

  networking.hostName = "Joels-MacBook-Pro";
  networking.computerName = "Joel's MacBook Pro";

  system.primaryUser = "joelschaeffer";
  users.users.joelschaeffer.home = "/Users/joelschaeffer";

  # Writes /etc/zshrc so every zsh sees the Nix profile paths.
  programs.zsh.enable = true;

  # Add an app here the day you need it, then `rebuild`. GUI apps land in
  # /Applications/Nix Apps. Find names with `nix search nixpkgs <name>`.
  environment.systemPackages = with pkgs; [
    ghostty-bin
    zed-editor
  ];

  # The prompt's icons need a Nerd Font.
  fonts.packages = [ pkgs.nerd-fonts.jetbrains-mono ];

  security.pam.services.sudo_local.touchIdAuth = true;

  system.defaults = {
    dock.autohide = true;
    dock.show-recents = false;
    finder.AppleShowAllExtensions = true;
    finder.FXPreferredViewStyle = "Nlsv";
    NSGlobalDomain.KeyRepeat = 2;
    NSGlobalDomain.InitialKeyRepeat = 15;
  };

  system.stateVersion = 7;
}
