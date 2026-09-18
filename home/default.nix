{ pkgs, ... }:

{
  home.username = "joelschaeffer";
  home.homeDirectory = "/Users/joelschaeffer";
  home.stateVersion = "25.11";

  home.packages = with pkgs; [
    nil
    nixfmt
  ];

  home.sessionVariables = {
    GOPATH = "/Users/joelschaeffer/.local/share/go";
    GOMODCACHE = "/Users/joelschaeffer/Library/Caches/go-mod";
    GOBIN = "/Users/joelschaeffer/.local/bin";
  };

  programs.home-manager.enable = true;

  programs.git = {
    enable = true;
    userName = "Joel Schaeffer";
    userEmail = "developers@lightwave-media.ltd";
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
