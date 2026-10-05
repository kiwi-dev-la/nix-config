# The forge's commands, rendered from declaration.nix. They bring the Forgejo
# the factory VM serves to the declared state and attach this host's Actions
# runner to it. Nothing is set up by hand and no secret is in this repo.
{ pkgs, lib, gitGuard }:

let
  forge = import ./declaration.nix;

  url = "http://127.0.0.1:${toString forge.port}";

  runnerLabels =
    if pkgs.stdenv.hostPlatform.isDarwin then forge.runner.labels.darwin else forge.runner.labels.linux;

  # The @...@ values are filled in when the runner starts.
  runnerConfig = pkgs.writeText "forgejo-runner.yaml" (builtins.toJSON {
    log.level = "info";
    runner = {
      inherit (forge.runner) capacity;
      labels = runnerLabels;
    };
    host.workdir_parent = "@RUNNER_HOME@/work";
    server.connections.forge = {
      url = "@FORGE_URL@";
      uuid = "@RUNNER_UUID@";
      token_url = "file:@FORGE_HOME@/secrets/runner_secret";
    };
  });

  command = name: extraInputs: pkgs.writeShellApplication {
    inherit name;
    runtimeInputs = [ pkgs.curl pkgs.jq pkgs.gnused pkgs.coreutils ] ++ extraInputs;
    # Every command gets the whole declaration and lib.sh; none uses all of it.
    excludeShellChecks = [ "SC2034" "SC2329" ];
    text = ''
      FORGE_URL="''${FORGE_URL:-${url}}"
      FORGE_ORG=${forge.org}
      FORGE_ADMIN="''${FORGE_ADMIN:-${forge.admin}}"
      FORGE_GITHUB_ORG=${forge.githubOrg}
      FORGE_REPOS=${lib.escapeShellArg (lib.concatStringsSep " " forge.repos)}
      FORGE_RUNNER_CONFIG=${runnerConfig}
    '' + builtins.readFile ./lib.sh + builtins.readFile (./. + "/${name}.sh");
  };

  commands = {
    forge-bootstrap = command "forge-bootstrap" [ ];
    forge-runner-up = command "forge-runner-up" [ pkgs.forgejo-runner ];
    forge-status = command "forge-status" [ ];
    forge-seed = command "forge-seed" [ pkgs.gh ];
  };
in
{
  packages = commands // {
    # The rendered template, to read what the runner is given.
    forge-runner-config = runnerConfig;
  };

  shell = pkgs.mkShell {
    packages = [ gitGuard pkgs.forgejo-runner pkgs.forgejo-cli pkgs.gh pkgs.jq ]
      ++ lib.attrValues commands;
    shellHook = ''
      export FORGE_URL="''${FORGE_URL:-${url}}"
      echo "forge shell: $FORGE_URL (state in ''${FORGE_HOME:-~/.local/state/forgejo})"
      echo "  forge-bootstrap   this host's token, the org and this host's runner"
      echo "  forge-runner-up   run this host's Actions runner"
      echo "  forge-seed        copy the fleet's repos from GitHub"
      echo "  forge-status      health check"
    '';
  };
}
