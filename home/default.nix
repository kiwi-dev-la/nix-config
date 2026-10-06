{ config, pkgs, lib, lightwave-ai, nixConfig, ... }:

{
  home.stateVersion = "26.11";

  home.packages = with pkgs; [
    # The rules in AGENTS.md, enforced: this `git` wins over the one
    # programs.git installs, in every shell and not only in dev shells.
    (lib.hiPrio (import ../rules/git-guard.nix { inherit pkgs lib; }))
    # Driving the factory from this Mac: `factory` (tickets, status, landing
    # on the forge; claude/factory) and `factory-vm` (the VM itself).
    (pkgs.writeShellApplication {
      name = "factory";
      runtimeInputs = with pkgs; [ curl jq git coreutils gnused gnugrep ];
      text = builtins.readFile ../claude/factory/factory.sh;
    })
    nixConfig.packages.${pkgs.stdenv.hostPlatform.system}.factory-vm
  ];

  # Claude Code, with the skills plugin the factory's workers use, pinned by
  # the same Nix fetch (lightwave-ai, factory/nix/skills.nix): it survives
  # the erase, and a plugin update is a pin move there, never a hand install.
  programs.claude-code = {
    enable = true;
    plugins.mattpocock-skills = lightwave-ai.packages.${pkgs.stdenv.hostPlatform.system}.mattpocock-skills;
    # How a session uses the factory: forge first, work as tickets (claude/factory).
    plugins.factory = ../claude/factory;
  };

  # Where GitButler's installer puts `but` (README, bootstrap step 6).
  home.sessionPath = [ "$HOME/.local/bin" ];

  # Cursor reads its skills from ~/.cursor/skills. They live under ~/.lightwave
  # with the rest of the agent-harness state, so that path is a link there.
  home.file.".cursor/skills".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.lightwave/skills";

  # GitButler's skill for each coding agent, written by `but` itself so it
  # matches the installed CLI. Runs on every rebuild, after the link above
  # exists; a Mac that has no `but` yet is told and skipped, never failed.
  home.activation.gitbutlerSkills = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run mkdir -p "$HOME/.lightwave/skills"
    but="$HOME/.local/bin/but"
    if [ -x "$but" ]; then
      for agent in .claude .codex .cursor; do
        run "$but" skill install --path "$HOME/$agent/skills/gitbutler" >/dev/null </dev/null ||
          echo "gitbutler: could not install the skill for $agent" >&2
      done
    else
      echo "gitbutler: not installed; README bootstrap step 6, then rebuild" >&2
    fi
  '';

  # `gh auth login` once (HTTPS); gh then signs git in for clone and push.
  programs.gh = {
    enable = true;
    gitCredentialHelper.enable = true;
    settings.git_protocol = "https";
  };

  # Claude Code updates only when flake.lock moves, never by itself.
  # No hidden memory: what an agent knows is in AGENTS.md files you can read.
  home.sessionVariables = {
    DISABLE_AUTOUPDATER = "1";
    CLAUDE_CODE_DISABLE_AUTO_MEMORY = "1";
  };

  # Shared rules for every repo under ~/dev. Agents read AGENTS.md files in
  # the working directory and every directory above it. Read-only symlink:
  # change it by editing AGENTS.md in this repo.
  home.file."dev/AGENTS.md".source = ../AGENTS.md;

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    historySubstringSearch.enable = true;
    history = {
      size = 100000;
      save = 100000;
      ignoreAllDups = true;
      share = true;
    };
    shellAliases = {
      ls = "eza";
      ll = "eza -lah --git";
      cat = "bat --paging=never";
      rebuild = "sudo darwin-rebuild switch --flake ~/dev/nix-config";
    };
    # This Mac's own shell setup, kept out of the repository (it holds
    # personal paths and keys): ~/.zshenv.local, ~/.zprofile.local and
    # ~/.zshrc.local, loaded last so they win, when they exist.
    envExtra = ''[ -f "$HOME/.zshenv.local" ] && . "$HOME/.zshenv.local"'';
    profileExtra = ''[ -f "$HOME/.zprofile.local" ] && . "$HOME/.zprofile.local"'';
    # After them, the Nix profile goes back in front: Homebrew's shellenv in a
    # local file would otherwise put its git ahead of the guarded one.
    initContent = lib.mkAfter ''
      [ -f "$HOME/.zshrc.local" ] && . "$HOME/.zshrc.local"
      path=("/etc/profiles/per-user/$USER/bin" "/run/current-system/sw/bin" $path)
      typeset -U path
    '';
  };

  programs.starship.enable = true;   # prompt
  programs.fzf.enable = true;        # Ctrl-R history search, Ctrl-T file picker
  programs.zoxide.enable = true;     # `z <part-of-dir>` jumps
  programs.eza.enable = true;
  programs.bat.enable = true;

  # cd into a repo with `.envrc` containing `use flake` and its devShell loads.
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    silent = true;
  };

  programs.git = {
    enable = true;
    settings = {
      user.name = "Joel Schaeffer";
      user.email = "developers@lightwave-media.ltd";
      init.defaultBranch = "main";
      pull.ff = "only";
    };
  };
}
