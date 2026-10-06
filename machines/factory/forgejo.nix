# Forgejo: the local forge. Issues, pull requests, merges and builds happen
# here; GitHub only ever receives a mirror of what has been proven.
#
# The same address works on the Mac and inside the VM:
#   web  http://127.0.0.1:3300
#   git  ssh://forgejo@127.0.0.1:2222/<owner>/<repo>.git
{ config, pkgs, ... }:
let
  cfg = config.services.forgejo;
  forge = import ../../forgejo/declaration.nix; # port, admin, runner labels
  httpPort = forge.port; # forwarded to the Mac in vm/default.nix
  sshPort = 2222; # the port vm/factory-vm.sh forwards to the VM's sshd
  runnerToken = "${cfg.stateDir}/runner-token";
in
{
  services.forgejo = {
    enable = true;
    lfs.enable = true;
    settings = {
      server = {
        HTTP_ADDR = "0.0.0.0";
        HTTP_PORT = httpPort;
        DOMAIN = "127.0.0.1";
        ROOT_URL = "http://127.0.0.1:${toString httpPort}/";
        SSH_PORT = sshPort;
      };
      # Reached over plain http on 127.0.0.1 only.
      session.COOKIE_SECURE = false;
      service.DISABLE_REGISTRATION = true;
      actions.ENABLED = true;
      # http://127.0.0.1:3300/metrics, for Prometheus.
      metrics.ENABLED = true;
    };
  };

  # sshd also answers on the forwarded port number, so git URLs are the same
  # inside the VM as on the Mac.
  services.openssh.ports = [ 22 sshPort ];
  networking.firewall.allowedTCPPorts = [ httpPort ];

  # First boot only: create the admin account with a generated password.
  # Read it with: factory-vm ssh sudo cat /var/lib/forgejo/admin-password
  systemd.services.forgejo-admin = {
    description = "Create the Forgejo admin account";
    wantedBy = [ "multi-user.target" ];
    after = [ "forgejo.service" ];
    requires = [ "forgejo.service" ];
    path = [ cfg.package pkgs.openssl ];
    environment = {
      USER = cfg.user;
      HOME = cfg.stateDir;
      FORGEJO_WORK_DIR = cfg.stateDir;
      FORGEJO_CUSTOM = cfg.customDir;
    };
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = cfg.user;
      Group = cfg.group;
      WorkingDirectory = cfg.stateDir;
      UMask = "0077";
    };
    script = ''
      secret=${cfg.stateDir}/admin-password
      if [ ! -e "$secret" ]; then
        openssl rand -hex 16 > "$secret.new"
        forgejo admin user create --admin --username ${forge.admin} --email ${forge.admin}@factory.local \
          --password "$(cat "$secret.new")" --must-change-password=false
        mv "$secret.new" "$secret"
      fi
      # The build runner's registration token, read by the runner below.
      if [ ! -e ${runnerToken} ]; then
        printf 'TOKEN=%s\n' "$(forgejo actions generate-runner-token)" > ${runnerToken}
      fi
    '';
  };

  # Forgejo Actions runner. Jobs with `runs-on: native` run directly on this
  # machine, with Nix available, so a workflow builds the same way a person
  # does here: `nix build`.
  services.gitea-actions-runner = {
    package = pkgs.forgejo-runner;
    instances.factory = {
      enable = true;
      name = "factory";
      url = "http://127.0.0.1:${toString httpPort}";
      tokenFile = runnerToken;
      labels = forge.runner.labels.linux;
      hostPackages = with pkgs; [ bash coreutils curl gawk git gnused jq nix nodejs wget ];
    };
  };
  systemd.services.gitea-runner-factory = {
    after = [ "forgejo-admin.service" ];
    requires = [ "forgejo-admin.service" ];
  };
}
