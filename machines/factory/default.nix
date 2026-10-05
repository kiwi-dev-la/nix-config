# The factory: a NixOS machine that runs as a VM on the Mac (see vm/).
# Everything dev-related and every always-on service lives here, not on macOS.
{ pkgs, modulesPath, ... }:
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

  environment.systemPackages = with pkgs; [ git curl jq htop ];

  system.stateVersion = "26.11";
}
