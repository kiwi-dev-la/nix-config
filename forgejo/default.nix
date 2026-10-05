# A Forgejo forge spawned from declaration.nix: the server, its Actions runner
# and the commands that drive it. Nothing is set up by hand and no secret is
# in this repo.
{ pkgs, lib, gitGuard }:

let
  forge = import ./declaration.nix;

  url = "http://127.0.0.1:${toString forge.port}";

  runnerLabels =
    if pkgs.stdenv.hostPlatform.isDarwin then forge.runner.labels.darwin else forge.runner.labels.linux;

  # nixpkgs flags Forgejo broken on Darwin and ships no binary for it. It
  # compiles there; one upstream test fails (TestGrepSearch in modules/git, the
  # code-search path), so on Darwin this is a source build with the test
  # phase off. Linux uses the stock, cached package.
  forgejo =
    if pkgs.stdenv.hostPlatform.isDarwin then
      pkgs.forgejo-lts.overrideAttrs (old: {
        doCheck = false;
        meta = old.meta // { broken = false; };
      })
    else
      pkgs.forgejo-lts;

  # @FORGE_HOME@ is the state directory, filled in when the server starts.
  appIni = pkgs.writeText "forgejo-app.ini" (lib.generators.toINIWithGlobalSection { } {
    globalSection = {
      APP_NAME = "Lightwave Forge";
      RUN_MODE = "prod";
      WORK_PATH = "@FORGE_HOME@";
    };
    sections = {
      server = {
        HTTP_ADDR = "127.0.0.1";   # loopback only
        HTTP_PORT = forge.port;
        DOMAIN = "localhost";
        ROOT_URL = "http://localhost:${toString forge.port}/";
        DISABLE_SSH = true;        # git over HTTP with a token
        OFFLINE_MODE = true;
        LFS_JWT_SECRET_URI = "file:@FORGE_HOME@/secrets/lfs_jwt_secret";
      };
      database = {
        DB_TYPE = "sqlite3";
        PATH = "@FORGE_HOME@/data/forgejo.db";
      };
      repository = {
        ROOT = "@FORGE_HOME@/repositories";
        DEFAULT_BRANCH = "main";
        DEFAULT_PRIVATE = "private";
      };
      security = {
        INSTALL_LOCK = true;       # no web installer; this file is the install
        SECRET_KEY_URI = "file:@FORGE_HOME@/secrets/secret_key";
        INTERNAL_TOKEN_URI = "file:@FORGE_HOME@/secrets/internal_token";
      };
      oauth2.JWT_SECRET_URI = "file:@FORGE_HOME@/secrets/jwt_secret";
      service.DISABLE_REGISTRATION = true;
      actions.ENABLED = true;
      packages.ENABLED = true;
      metrics.ENABLED = true;
      # forge-seed reads repos from github.com and their metadata from api.github.com.
      migrations.ALLOWED_DOMAINS = "github.com, *.github.com";
      webhook.ALLOWED_HOST_LIST = "loopback";
      log = {
        MODE = "console";
        LEVEL = "Info";
      };
    };
  });

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
    runtimeInputs = [ forgejo pkgs.curl pkgs.jq pkgs.gnused pkgs.gawk pkgs.coreutils ] ++ extraInputs;
    # Every command gets the whole declaration and lib.sh; none uses all of it.
    excludeShellChecks = [ "SC2034" "SC2329" ];
    text = ''
      FORGE_DECLARED_URL=${url}
      FORGE_URL="''${FORGE_URL:-$FORGE_DECLARED_URL}"
      FORGE_ORG=${forge.org}
      FORGE_ADMIN="''${FORGE_ADMIN:-${forge.admin}}"
      FORGE_GITHUB_ORG=${forge.githubOrg}
      FORGE_REPOS=${lib.escapeShellArg (lib.concatStringsSep " " forge.repos)}
      FORGE_APP_INI=${appIni}
      FORGE_RUNNER_CONFIG=${runnerConfig}
    '' + builtins.readFile ./lib.sh + builtins.readFile (./. + "/${name}.sh");
  };

  commands = {
    forge-up = command "forge-up" [ ];
    forge-bootstrap = command "forge-bootstrap" [ ];
    forge-runner-up = command "forge-runner-up" [ pkgs.forgejo-runner ];
    forge-status = command "forge-status" [ ];
    forge-seed = command "forge-seed" [ pkgs.gh ];
  };
in
{
  packages = commands // {
    inherit forgejo;
    # The rendered templates, to read what the server and runner are given.
    forge-app-ini = appIni;
    forge-runner-config = runnerConfig;
  };

  shell = pkgs.mkShell {
    packages = [ gitGuard forgejo pkgs.forgejo-runner pkgs.forgejo-cli pkgs.gh pkgs.jq ]
      ++ lib.attrValues commands;
    shellHook = ''
      export FORGE_URL="''${FORGE_URL:-${url}}"
      echo "forge shell: $FORGE_URL (state in ''${FORGE_HOME:-~/.local/state/forgejo})"
      echo "  forge-up          serve the forge from this host"
      echo "  forge-bootstrap   token, org and this host's runner (once the forge is up)"
      echo "  forge-runner-up   run this host's Actions runner"
      echo "  forge-seed        copy the fleet's repos from GitHub"
      echo "  forge-status      health check"
    '';
  };
}
