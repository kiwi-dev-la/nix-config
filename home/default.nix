{ pkgs, lib, ... }:

{
  home.stateVersion = "26.11";

  home.packages = with pkgs; [
    claude-code
    # The rules in AGENTS.md, enforced: this `git` wins over the one
    # programs.git installs, in every shell and not only in dev shells.
    (lib.hiPrio (import ../rules/git-guard.nix { inherit pkgs lib; }))
  ];

  # Where GitButler's installer puts `but` (README, bootstrap step 6).
  home.sessionPath = [ "$HOME/.local/bin" ];

  # GitButler's skill for each coding agent, written by `but` itself so it
  # matches the installed CLI. Runs on every rebuild; a Mac that has no `but`
  # yet is told and skipped, never failed.
  home.activation.gitbutlerSkills = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
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
