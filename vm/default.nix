# Commands for the factory VM (machines/factory), run on the Mac:
#   factory-vm     create, start, stop and update the VM (QEMU)
#   factory-prove  use the running factory for real and fail if anything is broken
{ pkgs, flake }:
let
  forge = import ../forgejo/declaration.nix;
  # Mac port -> VM port. The Mac's own ports are left alone; SSH is 2222 -> 22.
  forwards = {
    "${toString forge.port}" = forge.port; # Forgejo web
  };

  # Only used to get a first boot with SSH; NixOS replaces it during `up`.
  debianImage = pkgs.fetchurl {
    url = "https://cloud.debian.org/images/cloud/trixie/20261001-2618/debian-13-genericcloud-arm64-20261001-2618.qcow2";
    sha512 = "d8470b8c6c38fead046c794b5800a5a7b96672d5bcf543cc230ceb0c4b8ace05ed341a0c8928045422243fde26b2f1f2f58e99244c65709ffda2e3d4b674dd5a";
  };
in
rec {
  factory-vm = pkgs.writeShellApplication {
    name = "factory-vm";
    runtimeInputs = with pkgs; [
      qemu
      xorriso
      nixos-anywhere
      openssh
      coreutils
    ];
    runtimeEnv = {
      QEMU_SHARE = "${pkgs.qemu}/share/qemu";
      DEBIAN_IMAGE = "${debianImage}";
      FLAKE = "${flake}";
      FORWARDS = pkgs.lib.concatStringsSep " " (
        pkgs.lib.mapAttrsToList (mac: vm: "${mac}:${toString vm}") forwards
      );
    };
    text = builtins.readFile ./factory-vm.sh;
  };

  factory-prove = pkgs.writeShellApplication {
    name = "factory-prove";
    runtimeInputs = with pkgs; [
      factory-vm
      git
      curl
      jq
      coreutils
      gnused
      diffutils
    ];
    text = builtins.readFile ./factory-prove.sh;
  };
}
