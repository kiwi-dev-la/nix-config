# The factory: a NixOS machine that runs as a VM on the Mac (see vm/).
# Everything dev-related and every always-on service lives here, not on macOS.
{ config, pkgs, lib, modulesPath, lightwave-ai, ... }:
let
  forge = import ../../forgejo/declaration.nix;
in
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    ./disk.nix
    ./forgejo.nix
    ./forge-prune.nix
    lightwave-ai.nixosModules.factory
  ];

  # The factory: nulltickets, nullwatch, nullboiler and the gate as services,
  # one clone per declared repository, the hooks and personas from
  # lightwave-ai. Secrets are placed with `factory-vm secret set`.
  services.factory = {
    enable = true;
    forgeOwner = forge.org;
    # Every pull request the factory opens is reviewed by v_staff-engineer
    # (Claude Code) before it merges.
    # Workers per repository: work comes in bursts on one repository at a time,
    # so the busy ones get more. Not higher: a repository's workers share one
    # GitButler clone, and more of them mean more same-file conflicts.
    repos =
      let
        workers = { lightwave-ai = 5; nix-config = 3; };
      in
      map (name: { inherit name; workers = workers.${name} or 2; review = true; }) forge.repos;
    # The web page over the factory's services (nullhub embeds its dashboard).
    # Bound to 127.0.0.1 in the VM and not forwarded: it has no sign-in, so it
    # is reached through an ssh tunnel from the Mac only.
    nullhub.enable = true;
  };

  # The forge's service generates a token per factory account inside the VM
  # (machines/factory/forgejo.nix); this puts a copy where the factory user
  # reads them, mode 600, before the factory's own setup runs.
  systemd.services.factory-forge-tokens = {
    description = "Factory: the forge tokens of its accounts, for the factory user";
    wantedBy = [ "multi-user.target" ];
    after = [ "forgejo-admin.service" ];
    requires = [ "forgejo-admin.service" ];
    before = [ "factory-setup.service" "factory-gate.service" "factory-nullboiler.service" ];
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
    script = ''
      src=${config.services.forgejo.stateDir}/factory-tokens
      dest=${config.services.factory.secretsDir}
      install -d -m 700 -o ${config.services.factory.user} -g ${config.services.factory.group} "$dest"
      for account in ${lib.escapeShellArgs ([ forge.bot ] ++ forge.personas)}; do
        [ -s "$src/$account" ] || continue
        install -m 600 -o ${config.services.factory.user} -g ${config.services.factory.group} "$src/$account" "$dest/forgejo-token.$account"
      done
      # The package token, for workers installing @lightwave-media packages.
      if [ -s "$src/_packages" ]; then
        install -m 600 -o ${config.services.factory.user} -g ${config.services.factory.group} "$src/_packages" "$dest/forge-npm-token"
      fi
    '';
  };

  # The org's Actions secrets, from the factory's tokens: NODE_AUTH_TOKEN, the
  # GitHub Packages read token (`factory-vm secret set npm-token`), while
  # anything still installs from GitHub; FORGE_NPM_TOKEN, the forge's own
  # package token (forgejo-admin). Runs at boot and when npm-token changes.
  systemd.services.factory-forge-secrets = {
    description = "Factory: the org's CI secrets on the forge, from the factory's secrets";
    wantedBy = [ "multi-user.target" ];
    after = [ "forgejo-admin.service" ];
    requires = [ "forgejo-admin.service" ];
    path = [ pkgs.curl pkgs.jq ];
    serviceConfig.Type = "oneshot";
    script = ''
      admin=${config.services.forgejo.stateDir}/factory-tokens/_admin
      [ -s "$admin" ] || { echo "factory-forge-secrets: no admin token yet"; exit 0; }
      put() { # <name> <file>: the file's value as the org secret <name>
        [ -s "$2" ] || { echo "factory-forge-secrets: no $1 yet"; return 0; }
        # Both values reach curl on stdin, never as an argument.
        jq -Rn --rawfile t "$2" '{data: ($t | rtrimstr("\n"))}' |
          curl -fsS -m 30 -X PUT -H @<(printf 'Authorization: token %s\n' "$(cat "$admin")") \
            -H 'Content-Type: application/json' -d @- \
            http://127.0.0.1:${toString forge.port}/api/v1/orgs/${forge.org}/actions/secrets/"$1" >/dev/null
        echo "factory-forge-secrets: $1 set for ${forge.org}"
      }
      put NODE_AUTH_TOKEN ${config.services.factory.secretsDir}/npm-token
      put FORGE_NPM_TOKEN ${config.services.forgejo.stateDir}/factory-tokens/_packages
    '';
  };
  systemd.paths.factory-forge-secrets = {
    wantedBy = [ "multi-user.target" ];
    pathConfig.PathChanged = "${config.services.factory.secretsDir}/npm-token";
  };

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
  # Claude Code and GitButler (FSL) are unfree; nothing else on this machine is.
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "claude-code" "but" ];

  # The rules file agents read, at the top of the dev folder.
  systemd.tmpfiles.rules = [
    "d /home/joel/dev 0755 joel users -"
    "L+ /home/joel/dev/AGENTS.md - - - - ${../../AGENTS.md}"
  ];

  system.stateVersion = "26.11";
}
