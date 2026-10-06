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

  # The one workflow every repo carries: one job per declared runner kind
  # (the label before the colon: `macos`, `native`), as a matrix.
  runnerKinds = map (label: builtins.head (lib.splitString ":" label)) (lib.concatLists (lib.attrValues forge.runner.labels));
  workflow =
    assert lib.elem forge.ci.runsOn runnerKinds;
    pkgs.writeText "forge-ci-workflow.yml"
      (builtins.replaceStrings [ "@RUNNERS@" ] [ (lib.concatStringsSep ", " runnerKinds) ] (builtins.readFile ./workflow.yml));

  # The one command that workflow runs. A runner puts it on its jobs' PATH.
  # The gate gets mise from here and everything else from the runner's host.
  forge-ci = pkgs.writeShellApplication {
    name = "forge-ci";
    runtimeInputs = [ pkgs.mise ];
    text = ''
      GIT=${pkgs.git}/bin/git
      NO_GLOBAL_CONFIG=${pkgs.writeText "mise-global.toml" ""}
    '' + builtins.readFile ./forge-ci.sh;
  };

  command = name: extraInputs: let
    inputs = [ pkgs.curl pkgs.jq pkgs.gnused pkgs.coreutils pkgs.diffutils ] ++ extraInputs;
  in pkgs.writeShellApplication {
    inherit name;
    runtimeInputs = inputs;
    # Every command gets the whole declaration and lib.sh; none uses all of it.
    excludeShellChecks = [ "SC2034" "SC2329" ];
    text = ''
      FORGE_URL="''${FORGE_URL:-${url}}"
      FORGE_ORG=${forge.org}
      FORGE_ADMIN="''${FORGE_ADMIN:-${forge.admin}}"
      FORGE_GITHUB_ORG=${forge.githubOrg}
      FORGE_GITHUB_SOURCES=${lib.escapeShellArg (lib.concatStringsSep " " (lib.mapAttrsToList (r: o: "${r}=${o}") (forge.githubSources or { })))}
      FORGE_REPOS=${lib.escapeShellArg (lib.concatStringsSep " " forge.repos)}
      FORGE_RUNNER_CONFIG=${runnerConfig}
      FORGE_WORKFLOW=${workflow}
      FORGE_FLEET_NIX=${./fleet.nix}
      FORGE_CI_BIN=${forge-ci}/bin
      FORGE_TOOL_PATH=${lib.makeBinPath inputs}
    '' + builtins.readFile ./lib.sh + builtins.readFile (./. + "/${name}.sh");
  };

  commands = rec {
    forge-bootstrap = command "forge-bootstrap" [ ];
    forge-runner-up = command "forge-runner-up" [ pkgs.forgejo-runner ];
    forge-status = command "forge-status" [ ];
    # Seeding ends by stamping, so no repo sits in the forge with only the
    # workflows it arrived with.
    forge-seed = command "forge-seed" [ pkgs.gh forge-workflows ];
    forge-workflows = command "forge-workflows" [ ];
  };
in
{
  packages = commands // {
    inherit forge-ci;
    # The rendered templates, to read what the runner and the repos are given.
    forge-runner-config = runnerConfig;
    forge-workflow = workflow;
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
      echo "  forge-workflows   put the fleet's CI workflow in every repo"
      echo "  forge-status      health check"
    '';
  };
}
