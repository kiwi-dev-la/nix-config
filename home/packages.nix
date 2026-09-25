# Every CLI tool on this Mac comes from Nix. Nix is the Lightwave package
# manager for all environments; Homebrew is legacy (hosts/homebrew.nix holds
# only what nixpkgs cannot provide yet).
#
# Migrated 2026-09-25 from `brew leaves` (90 formulae). Each entry below is the
# nixpkgs equivalent of a formula that was installed by hand; the formulae
# themselves are left in place (homebrew.onActivation.cleanup = "none") until
# the launchd agents that put /opt/homebrew/bin on PATH are repointed.
#
# Not here, on purpose:
#   lw          - the flake's lightwave-cli input, installed by `mise run lw:sync`
#   git, direnv - configured by programs.git / programs.direnv in default.nix
#   postgresql@17 + pgvector, redis, ollama, tailscale, forgejo - daemons that
#                 run from Homebrew today; moving a running service is its own
#                 change (no launchd agents in nix-darwin until the nullstack
#                 and Forgejo plist sets are final)
#   checkov     - nixpkgs refuses it: depends on insecure python ecdsa
#                 (CVE-2024-23342); stays a Homebrew formula, unused by any repo
#   gitea-runner, python-tk@3.12, git-gui - unused here (the Forgejo runner is
#                 ~/.local/bin/forgejo-runner; git-gui ships with git)
{ pkgs, ... }:

{
  home.packages = with pkgs; [
    # --- shell and everyday CLI
    bat
    btop
    eza
    fd
    fzf
    gum
    httpie
    jless
    just
    ripgrep
    tmux
    tree
    watchexec
    yq
    zoxide

    # --- git, GitHub, Forgejo
    act
    actionlint
    codespell
    delta # brew: git-delta
    forgejo-cli
    gh
    git-filter-repo
    gitleaks
    yamllint

    # --- toolchains and build
    beamPackages.elixir # brew: elixir
    go
    goreleaser
    mise
    nil
    nixfmt
    swig
    uv
    zig

    # --- cloud, infra, secrets
    awscli2 # brew: awscli (v2)
    chamber
    cf-terraforming
    cloud-nuke
    cloudflared
    kubernetes-helm # brew: helm
    linode-cli
    opentofu
    rclone
    sentry-cli
    stripe-cli # brew: stripe/stripe-cli/stripe
    terraform # unfree; brew: hashicorp/tap/terraform
    terragrunt
    tflint

    # --- supply chain and certificates
    grype
    mkcert
    syft
    trivy

    # --- Google, AI
    gemini-cli
    gogcli # brew: openclaw/tap/gogcli
    gws # brew: googleworkspace-cli

    # --- media, documents
    antiword
    exiftool
    ffmpeg
    file # provides libmagic; brew: libmagic
    ghostscript
    imagemagick
    pandoc
    poppler
    potrace
    sox
    unrtf
    whisper-cpp # brew: whisper.cpp
    yt-dlp

    # --- macOS
    mas
    switchaudio-osx
  ];
}
