# This Mac's Actions runner as a boot-time launchd daemon (a nix-darwin
# module), run as its own macOS user, `_forgejo-runner`: no admin, no login
# shell, its own home. A job can read that home and what the world can read,
# not Joel's home, keys, browser data or iCloud. Its `git` is the git guard,
# and Nix is the machine's Nix daemon; the Nix caches and the checkouts live in
# its home, so builds stay warm between runs.
#
# It registers itself on first start with the forge's runner token, placed by
# `factory-vm runner-token` (fetched from the VM, never in this repo).
{ pkgs, lib, ... }:
let
  forge = import ./declaration.nix;
  gitGuard = import ../rules/git-guard.nix { inherit pkgs lib; };
  forgeCommands = import ./. { inherit pkgs lib gitGuard; };

  name = "_forgejo-runner";
  id = 380;
  home = "/var/lib/forgejo-runner";
  log = "/var/log/forgejo-runner.log";

  labels = forge.runner.labels.darwin;

  # The runner registers in <home>/.runner; jobs run in <home>/work, one
  # lasting checkout per repository.
  runnerConfig = pkgs.writeText "forgejo-runner.yaml" (builtins.toJSON {
    log.level = "info";
    runner = {
      file = "${home}/.runner";
      inherit (forge.runner) capacity;
      inherit labels;
    };
    cache.dir = "${home}/cache";
    host.workdir_parent = "${home}/work";
  });

  # `factory-vm runner-token` places the registration token here, readable by
  # the runner's user only.
  tokenFile = "${home}/registration-token";

  runner = pkgs.writeShellApplication {
    name = "forge-mac-runner";
    runtimeInputs = [ pkgs.forgejo-runner pkgs.curl pkgs.coreutils pkgs.gnused ];
    text = ''
      FORGE_URL=''${FORGE_URL:-http://127.0.0.1:${toString forge.port}}
      HOME=${home}
      export HOME
      cd "$HOME"
      mkdir -p work cache
      echo "forge-mac-runner: user $(id -un), home $HOME"

      # The forge is a VM that can come up after this Mac does.
      until curl --fail --silent --max-time 2 "$FORGE_URL/api/healthz" >/dev/null; do
        echo "forge-mac-runner: waiting for the forge at $FORGE_URL" >&2
        sleep 5
      done

      if [ ! -s .runner ]; then
        until [ -s ${tokenFile} ]; do
          echo "forge-mac-runner: no runner token at ${tokenFile}; run: factory-vm runner-token" >&2
          sleep 30
        done
        # The token is the file's TOKEN=... line. register reads its answers
        # on stdin, so the token is on no command line.
        token="$(sed -n 's/^TOKEN=//p' ${tokenFile})"
        printf '%s\n%s\n%s\n%s\n' "$FORGE_URL" "$token" "$(hostname -s)-macos" ${lib.concatStringsSep "," labels} |
          forgejo-runner register --config ${runnerConfig}
      fi

      # Jobs get this PATH: forge-ci and the git guard first, then Nix and the system's tools.
      exec env PATH="${forgeCommands.packages.forge-ci}/bin:${gitGuard}/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
        ${pkgs.forgejo-runner}/bin/forgejo-runner daemon --config ${runnerConfig}
    '';
  };
in
{
  users.knownUsers = [ name ];
  users.knownGroups = [ name ];
  users.groups.${name} = {
    gid = id;
    description = "Forgejo Actions runner";
  };
  users.users.${name} = {
    uid = id;
    gid = id;
    inherit home;
    createHome = true;
    shell = "/usr/bin/false";
    isHidden = true;
    description = "Forgejo Actions runner";
  };

  # The home is the runner's alone (the token in it is read from here).
  system.activationScripts.postActivation.text = ''
    mkdir -p ${home}
    chown ${name}:${name} ${home}
    chmod 700 ${home}
    touch ${log}
    chown ${name}:${name} ${log}
  '';

  launchd.daemons.forgejo-runner = {
    command = "${runner}/bin/forge-mac-runner";
    serviceConfig = {
      UserName = name;
      GroupName = name;
      WorkingDirectory = home;
      EnvironmentVariables.HOME = home;
      RunAtLoad = true;
      KeepAlive = true;
      ThrottleInterval = 30;
      StandardOutPath = log;
      StandardErrorPath = log;
    };
  };
}
