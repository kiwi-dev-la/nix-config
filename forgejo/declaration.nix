# The one declaration of the forge. default.nix renders the server, the runner
# and the forge-* commands from it. A machine that hosts the forge reads the
# same values: `import ../../forgejo/declaration.nix`.
{
  port = 3600;
  org = "lightwave-media";
  admin = "forge-admin";
  runner = {
    capacity = 1;
    # What a workflow's `runs-on` asks for, by the kind of host the runner is on.
    labels = {
      darwin = [ "macos:host" ];   # `runs-on: macos`
      linux = [ "native:host" ];   # `runs-on: native`
    };
  };
  # forge-seed copies these from github.com/<githubOrg>.
  githubOrg = "lightwave-media";
  repos = [
    "lightwave-core"
    "lightwave-cli"
    "lightwave-ai"
    "lightwave-platform"
    "lightwave-plugin"
    "lightwave-ui"
    "lightwave-sys"
    "lightwave-infrastructure-catalog"
    "lightwave-infrastructure-live"
    "lightwave-media-site"
    "joelschaeffer-site"
    "createOS"
    "pipelines-workflows"
  ];
}
