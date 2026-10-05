# This Mac's Actions runner as a login service (a nix-darwin module). launchd
# starts it once forge-bootstrap has registered the runner and keeps it
# running from then on. It takes `runs-on: macos` jobs.
{ config, pkgs, lib, ... }:
let
  forge = import ./. {
    inherit pkgs lib;
    gitGuard = import ../rules/git-guard.nix { inherit pkgs lib; };
  };
  user = config.system.primaryUser;
  home = config.users.users.${user}.home;
  log = "${home}/Library/Logs/forge-runner.log";
in
{
  launchd.user.agents.forge-runner = {
    command = "${forge.packages.forge-runner-up}/bin/forge-runner-up";
    # Jobs get the tools a login shell has, the git guard included.
    path = [
      "/etc/profiles/per-user/${user}/bin"
      "/run/current-system/sw/bin"
      "/nix/var/nix/profiles/default/bin"
      "/usr/bin"
      "/bin"
      "/usr/sbin"
      "/sbin"
    ];
    serviceConfig = {
      KeepAlive.PathState."${home}/.local/state/forgejo/secrets/runner_secret" = true;
      ThrottleInterval = 30;
      StandardOutPath = log;
      StandardErrorPath = log;
    };
  };
}
