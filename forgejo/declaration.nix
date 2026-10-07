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
  # Who drives the factory from outside it: Claude Code on the Mac, so its
  # issues, merges and syncs carry its own name and not the owner's. Same
  # team and token scopes as the personas; its token stays in the VM's token
  # folder and is fetched by the Mac (`factory login`).
  operators = [ "claude-code" ];
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
  # Repos whose GitHub copy lives under another owner than githubOrg.
  githubSources = { nix-config = "kiwi-dev-la"; };
  # What the VM's forgejo-admin applies on every boot and switch, through the
  # API with the admin token: it creates what is missing and puts back what a
  # hand change moved, logging each correction.
  policy = {
    # Branch protection of every repository's main; `branchProtection` is the
    # Forgejo API's own field names. `overrides.<repo>` replaces single fields.
    branch = "main";
    branchProtection = {
      enable_push = true;
      enable_push_whitelist = true;
      push_whitelist_usernames = [ "joel" ];
      enable_status_check = true;
      status_check_contexts = [ "ci / ci (native) (pull_request)" ];
      required_approvals = 0;
    };
    overrides = {
      nix-config = {
        required_approvals = 1;
        enable_approvals_whitelist = true;
        approvals_whitelist_username = [ "joel" "claude-code" "v_staff-engineer" ];
        protected_file_patterns = "rules/**";
        block_on_rejected_reviews = true;
        dismiss_stale_approvals = true;
      };
    };
    # Repository settings (PATCH /repos/{org}/{repo}).
    settings = {
      default_delete_branch_after_merge = true;
      has_actions = true;
    };
    # Labels of the org (shared by every repository), and of each repository.
    orgLabels = [
      { name = "Kind/Bug"; color = "ee0701"; description = "Something is broken"; }
      { name = "Kind/Feature"; color = "0288d1"; description = "New functionality"; }
      { name = "Kind/Enhancement"; color = "84b6eb"; description = "Improve existing functionality"; }
      { name = "Kind/Documentation"; color = "37474f"; description = "Documentation changes"; }
      { name = "Kind/Security"; color = "e11d21"; description = "Security related"; }
      { name = "Kind/Testing"; color = "795548"; description = "Tests"; }
      { name = "Priority/Critical"; color = "e11d21"; description = "The highest priority"; }
      { name = "Priority/High"; color = "ee9a00"; description = "High priority"; }
      { name = "Priority/Medium"; color = "fbca04"; description = "Medium priority"; }
      { name = "Priority/Low"; color = "0e8a16"; description = "Low priority"; }
      { name = "Status/Blocked"; color = "880e4f"; description = "Waiting on something else"; }
      { name = "Status/In Progress"; color = "1d76db"; description = "Being worked on"; }
      { name = "Status/Need More Info"; color = "a2eeef"; description = "Feedback is required"; }
      { name = "Status/Abandoned"; color = "cccccc"; description = "Will not be worked on"; }
    ];
    # The intake filter: the factory picks up issues carrying this label.
    repoLabels = [
      { name = "factory"; color = "5319e7"; description = "Taken by the factory"; }
    ];
  };
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
    # This repository: the forge, the factory and the Mac, changed through the
    # factory like any other (CODEOWNERS names who approves what).
    "nix-config"
  ];
}
