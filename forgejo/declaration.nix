# The one declaration of the forge. The factory VM (machines/factory) serves
# it; default.nix renders the forge-* commands and this host's runner from it.
{
  port = 3300;
  org = "lightwave-media";
  admin = "joel";   # made by the VM on first boot
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
