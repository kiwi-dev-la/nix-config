# The factory: a NixOS machine that runs as a VM on the Mac (see vm/).
# Everything dev-related and every always-on service lives here, not on macOS.
{ pkgs, lib, modulesPath, ... }:
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    ./disk.nix
    ./forgejo.nix
  ];

  networking.hostName = "factory";
  time.timeZone = "America/Los_Angeles";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # The VM's console is a serial port; vm/factory-vm.sh writes it to console.log.
  boot.kernelParams = [ "console=ttyAMA0" ];

  # Keys only. The public key is put in /etc/ssh/authorized_keys.d at install
  # time by vm/factory-vm.sh, so no key is kept in this (public) repository.
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  users.users.joel = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
  };
  security.sudo.wheelNeedsPassword = false;

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" "joel" ];
    auto-optimise-store = true;
  };
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # AGENTS.md is enforced here as on the Mac: `git` is the guard, which refuses
  # worktrees, raw branch creation, AI attribution and pushes that carry secrets.
  environment.systemPackages = with pkgs; [
    (lib.hiPrio (import ../../rules/git-guard.nix { inherit pkgs lib; }))
    git
    curl
    jq
    htop
    # The factory's workers and their live view.
    claude-code
    tmux
    sqlite
  ];
  # Claude Code is unfree; nothing else on this machine is.
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "claude-code" ];

  # The rules file agents read, at the top of the dev folder.
  systemd.tmpfiles.rules = [
    "d /home/joel/dev 0755 joel users -"
    "L+ /home/joel/dev/AGENTS.md - - - - ${../../AGENTS.md}"
  ];

  system.stateVersion = "26.11";
}
