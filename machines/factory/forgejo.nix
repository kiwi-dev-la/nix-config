# Forgejo: the local forge. Issues, pull requests, merges and builds happen
# here; GitHub only ever receives a mirror of what has been proven.
#
# The same address works on the Mac and inside the VM:
#   web  http://127.0.0.1:3300
#   git  ssh://forgejo@127.0.0.1:2222/<owner>/<repo>.git
{ config, pkgs, lib, ... }:
let
  cfg = config.services.forgejo;
  forge = import ../../forgejo/declaration.nix; # port, admin, runner labels
  # The fleet's one CI command, which every repository's workflow runs.
  forgeTools = import ../../forgejo { inherit pkgs lib; gitGuard = import ../../rules/git-guard.nix { inherit pkgs lib; }; };
  httpPort = forge.port; # forwarded to the Mac in vm/default.nix
  sshPort = 2222; # the port vm/factory-vm.sh forwards to the VM's sshd
  runnerToken = "${cfg.stateDir}/runner-token";
  factoryTokens = "${cfg.stateDir}/factory-tokens";
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
      # Webhooks may call the factory's receiver inside this machine.
      webhook.ALLOWED_HOST_LIST = "loopback";
      # The org's npm (and container) registry: the fleet installs
      # @lightwave-media packages from here, not from GitHub Packages.
      packages.ENABLED = true;
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
    path = [ cfg.package pkgs.openssl pkgs.curl pkgs.jq pkgs.gawk ];
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

      # The factory's accounts (forgejo/declaration.nix): the personas and the
      # gate's bot, each with a token generated here and never shown. The
      # factory machine copies the tokens into the factory user's secrets
      # (factory-forge-tokens in default.nix).
      tokens=${factoryTokens}
      mkdir -p "$tokens"
      for account in ${lib.escapeShellArgs ([ forge.bot ] ++ forge.personas ++ forge.operators)}; do
        if ! forgejo admin user list | awk '{print $2}' | grep -qx "$account"; then
          forgejo admin user create --username "$account" --email "$account@factory.local" \
            --password "$(openssl rand -hex 16)" --must-change-password=false
        fi
        if [ ! -s "$tokens/$account" ]; then
          forgejo admin user generate-access-token --username "$account" --token-name factory --raw \
            --scopes write:repository,write:issue,write:organization,write:user,read:misc > "$tokens/$account.new" \
            && mv "$tokens/$account.new" "$tokens/$account"
        fi
      done
      # The admin's own token, for the team below; stays here.
      if [ ! -s "$tokens/_admin" ]; then
        forgejo admin user generate-access-token --username ${forge.admin} --token-name factory-admin --raw \
          --scopes write:organization,write:repository,write:user > "$tokens/_admin.new" && mv "$tokens/_admin.new" "$tokens/_admin"
      fi

      # The team `factory` with write on every repository of the org, holding
      # the accounts. The org itself comes from forge-bootstrap (run from the
      # Mac); until it exists this is skipped and done at the next start.
      api() { curl -fsS -m 10 -H "Authorization: token $(cat "$tokens/_admin")" -H 'Content-Type: application/json' "$@"; }
      base=http://127.0.0.1:${toString httpPort}/api/v1
      if api "$base/orgs/${forge.org}" >/dev/null 2>&1; then
        team=$(api "$base/orgs/${forge.org}/teams" | jq -r '.[] | select(.name == "factory") | .id')
        if [ -z "$team" ]; then
          team=$(api -X POST "$base/orgs/${forge.org}/teams" -d '{"name":"factory","description":"The factory: its personas and its gate","permission":"write","includes_all_repositories":true,"can_create_org_repo":false,"units":["repo.code","repo.issues","repo.pulls","repo.releases","repo.wiki","repo.projects","repo.actions"]}' | jq -r .id)
        fi
        for account in ${lib.escapeShellArgs ([ forge.bot ] ++ forge.personas ++ forge.operators)}; do
          api -X PUT "$base/teams/$team/members/$account" >/dev/null 2>&1 || echo "forgejo-admin: could not add $account to the factory team" >&2
        done
      else
        echo "forgejo-admin: no org ${forge.org} yet (forge-bootstrap); the factory team waits for the next start" >&2
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
      hostPackages = [ forgeTools.packages.forge-ci ]
        ++ (with pkgs; [ bash coreutils curl gawk git gnused jq nix nodejs wget ]);
    };
  };
  systemd.services.gitea-runner-factory = {
    after = [ "forgejo-admin.service" ];
    requires = [ "forgejo-admin.service" ];
    # A real user, not systemd's dynamic one. A dynamic user's state folder is
    # mounted noexec (no checked-out script could run) and reached through a
    # symlink (/var/lib/gitea-runner -> /var/lib/private/gitea-runner), which
    # breaks a build that walks `../` from one to the other (lightwave-sys's
    # zig dependency spawning its own build tool). systemd moves the state back
    # out of /var/lib/private when DynamicUser goes off.
    serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = "gitea-runner";
      Group = "gitea-runner";
    };
  };
  users.users.gitea-runner = {
    isSystemUser = true;
    group = "gitea-runner";
    home = "/var/lib/gitea-runner";
  };
  users.groups.gitea-runner = { };
  # The move out of /var/lib/private keeps the dynamic user's ownership
  # (nobody), so the runner could not write its own cache; owned by the real
  # user on every boot and switch.
  systemd.tmpfiles.rules = [ "Z /var/lib/gitea-runner - gitea-runner gitea-runner -" ];
}
