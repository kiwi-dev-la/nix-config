# The git every shell built from this repo uses: the rules in AGENTS.md, in
# front of the real git.
{ pkgs, lib }:

let
  # Commit trailers and footers that name a model or a tool as the author.
  # Matched case-insensitively.
  aiAttribution = "co-authored-by:.*(claude|anthropic|codex|openai|copilot|cursor|gemini)|generated with .?(claude|codex|cursor)";
in
pkgs.writeShellApplication {
  name = "git";
  text = ''
    REAL_GIT=${pkgs.git}/bin/git
    GITLEAKS=${pkgs.gitleaks}/bin/gitleaks
    AI_ATTRIBUTION=${lib.escapeShellArg aiAttribution}
  '' + builtins.readFile ./git-guard.sh;
}
