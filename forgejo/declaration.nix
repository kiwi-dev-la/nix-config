# The one declaration of the forge. The factory VM (machines/factory) serves
# it; default.nix renders the forge-* commands and this host's runner from it.
{
  port = 3300;
  org = "lightwave-media";
  admin = "joel";   # made by the VM on first boot
  # The factory's own accounts, made by the VM with a token each generated
  # inside it (machines/factory/forgejo.nix): one per persona, so every
  # commit, pull request and review carries its author, and the gate's bot.
  # They form the team `factory` with write on every repository of the org.
  personas = [ "v_developer" "v_engineer" "v_staff-engineer" "v_cto" "jev" ];
  bot = "factory";
  runner = {
    capacity = 1;
    # What a workflow's `runs-on` asks for, by the kind of host the runner is on.
    labels = {
      darwin = [ "macos:host" ];   # `runs-on: macos`
      linux = [ "native:host" ];   # `runs-on: native`
    };
  };
  # Every repo's CI runs one job per runner kind (the labels above: `macos`
  # on the Mac, `native` on the factory VM). This one is the runner a person
  # expects to see the gate on; the factory's merge needs the VM's job.
  ci.runsOn = "macos";
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
