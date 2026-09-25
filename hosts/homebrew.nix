# Homebrew, managed BY Nix. Only what nixpkgs cannot provide yet, or a daemon
# that runs from Homebrew today, is declared here; every CLI tool is in
# home/packages.nix.
#
# Non-destructive on purpose (phase 1):
#   cleanup = "none"  - formulae not listed here are left installed. Launchd
#                       agents still put /opt/homebrew/bin on PATH, so removing
#                       a formula now would pull a binary out from under them.
#   autoUpdate/upgrade = false - a switch never upgrades anything by surprise.
# Phase 2 flips cleanup to "uninstall" once those agents are repointed at Nix.
{ ... }:

{
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = false;
      upgrade = false;
      cleanup = "none";
    };

    taps = [
      "antoniorodr/memo"
      "openclaw/tap"
      "steipete/tap"
    ];

    brews = [
      # not in nixpkgs
      "antoniorodr/memo/memo"
      "git-xargs"
      "ical-buddy"
      "neonctl"
      "openclaw/tap/goplaces"
      "openclaw/tap/wacli"
      "steipete/tap/peekaboo"
      "steipete/tap/remindctl"
      "summarize"
      # nixpkgs' checkov depends on python ecdsa, marked insecure
      # (CVE-2024-23342, which upstream will not fix). Permitting an insecure
      # package is the operator's call; no lightwave repo references checkov,
      # so this is a candidate for removal rather than for an exception.
      "checkov"
      # daemons that run from Homebrew today (see home/packages.nix)
      "forgejo" # nixpkgs' forgejo is not available on darwin
      "ollama"
      "pgvector"
      "postgresql@17"
      "redis"
      "tailscale"
    ];

    # GUI apps and app-integrated CLIs stay casks for now.
    casks = [
      "1password-cli"
      "gcloud-cli"
      "ghostty"
      "goplaces"
      "lm-studio"
      "ngrok"
      "zed"
    ];
  };
}
