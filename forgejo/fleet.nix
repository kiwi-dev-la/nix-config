# The fleet's per-repository Nix, the same file in every repository of the
# forge as nix/fleet.nix. It is stamped by `forge-workflows` from
# kiwi-dev-la/nix-config (forgejo/fleet.nix), beside the CI workflow; change it
# there, not here: a copy that differs fails `forge-status`.
#
# A repository's flake.nix names its kinds and adds only what is its own:
#
#   inputs.nixpkgs.url = "github:NixOS/nixpkgs/79b35bf0bda5cd110f856aa5b5b2c5ba4460dbf5";
#   outputs = { self, nixpkgs }: import ./nix/fleet.nix {
#     inherit nixpkgs;
#     name = "my-repo";
#     kinds = [ "go" "node" ];                     # the templates below
#     tools = pkgs: [ pkgs.goreleaser ];           # beyond what the kinds bring
#     gate = [ "go vet ./..." "go test ./..." ];   # replaces the kinds' gate
#     shell = pkgs: {                              # the repository's own shell:
#       inputsFrom = [ (import ./nix/devShell.nix { inherit pkgs; }) ];
#       shellHook = "unset OPENROUTER_API_KEY";    # env, hooks, a richer shell
#     };
#   };
#
# and gets:
#   devShells.default  the kinds' tools, the repository's own, and what every
#                      gate uses (bash, coreutils, git, jq ...): `nix develop`,
#                      and the shell every factory worker in a clone enters
#   apps.ci            the gate: each step in order, from the repository's
#                      root, inside that same dev shell (its compiler
#                      environment, SDK and hooks included); `nix run .#ci` is
#                      what the forge's runner runs (forge-ci). Without
#                      `gate`, the kinds' own steps, in kind order.
#
# Every repository pins the same nixpkgs (above) so one store serves them all.
# Other outputs (packages, checks, modules) are the repository's own; merge
# them deeply so the repository's apps sit beside `ci`:
# `nixpkgs.lib.recursiveUpdate (import ./nix/fleet.nix { ... }) { packages = ...; }`.
{ nixpkgs
, name
, kinds ? [ ]
, tools ? (pkgs: [ ])
, gate ? null
, shell ? (pkgs: { })
, systems ? [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ]
  # A gate step that runs longer is stopped and fails the gate, so a hung
  # test costs minutes, not the job's whole hour.
, stepTimeout ? "20m"
}:
let
  inherit (nixpkgs) lib;
  forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

  # One template per kind of repository: its tools, and the gate a
  # repository of that kind gets when it declares none.
  templates = {
    zig = {
      tools = pkgs: [ pkgs.zig pkgs.zls ];
      gate = [ "zig build test --summary all" ];
    };
    # Repositories still on zig 0.15. On macOS, zig 0.15 cannot link
    # against the system's newer SDKs; it gets nixpkgs' SDK instead.
    "zig-0.15" = {
      tools = pkgs: [ pkgs.zig_0_15 pkgs.zls_0_15 ]
        ++ lib.optional pkgs.stdenv.hostPlatform.isDarwin pkgs.apple-sdk_15;
      gate = [ "zig build test --summary all" ];
    };
    go = {
      # A C compiler: `go test -race` needs cgo.
      tools = pkgs: [ pkgs.go pkgs.gopls pkgs.golangci-lint pkgs.stdenv.cc ];
      gate = [ "test -z \"$(gofmt -l .)\"" "go vet ./..." "go test ./..." ];
      # A GOROOT exported by another Go (mise, Homebrew) breaks Nix's Go.
      shellHook = "unset GOROOT";
    };
    rust = {
      tools = pkgs: [ pkgs.rustc pkgs.cargo pkgs.clippy pkgs.rustfmt pkgs.pkg-config pkgs.stdenv.cc ]
        ++ lib.optional pkgs.stdenv.hostPlatform.isDarwin pkgs.libiconv;
      gate = [ "cargo fmt --check" "cargo clippy -- -D warnings" "cargo test" ];
    };
    node = {
      tools = pkgs: [ pkgs.nodejs_24 ];
      gate = [ "npm ci" "npm test" ];
    };
    pnpm = {
      tools = pkgs: [ pkgs.nodejs_24 pkgs.pnpm ];
      gate = [ "pnpm install --frozen-lockfile" "pnpm test" ];
    };
    bun = {
      tools = pkgs: [ pkgs.bun ];
      gate = [ "bun install --frozen-lockfile" "bun test" ];
    };
    hugo = {
      tools = pkgs: [ pkgs.hugo ];
      gate = [ "hugo --gc --minify" ];
    };
    python = {
      tools = pkgs: [ pkgs.python312 ];
      gate = [ "python3 -m unittest discover" ];
    };
    terragrunt = {
      tools = pkgs: [ pkgs.opentofu pkgs.terragrunt ];
      gate = [ "tofu fmt -check -recursive" "terragrunt hcl format --check" ];
    };
    shell = {
      tools = pkgs: [ pkgs.shellcheck pkgs.actionlint ];
      gate = [ "git ls-files -z '*.sh' | xargs -0 -r shellcheck" ];
    };
  };

  unknown = lib.subtractLists (lib.attrNames templates) kinds;
  chosen = assert lib.assertMsg (unknown == [ ])
    "nix/fleet.nix: no template for kind(s) ${lib.concatStringsSep ", " unknown}; known: ${lib.concatStringsSep ", " (lib.attrNames templates)}";
    map (k: templates.${k}) kinds;

  # What the gate's own steps and the fleet's scripts call, on every host.
  base = pkgs: with pkgs; [ bash coreutils diffutils findutils gnugrep gnused gawk git jq ];
  everything = pkgs: lib.unique (base pkgs ++ lib.concatMap (t: t.tools pkgs) chosen ++ tools pkgs);
  steps = if gate != null then gate else lib.concatMap (t: t.gate) chosen;
  hooks = lib.concatStringsSep "\n" (lib.filter (h: h != "") (map (t: t.shellHook or "") chosen));
  devShell = pkgs:
    let own = shell pkgs; in
    pkgs.mkShell (own // {
      packages = everything pkgs ++ (own.packages or [ ]);
      shellHook = lib.concatStringsSep "\n" (lib.filter (h: h != "") [ hooks (own.shellHook or "") ]);
    });
in
assert lib.assertMsg (steps != [ ]) "nix/fleet.nix: ${name} has no gate: name a kind or list the steps";
{
  devShells = forAllSystems (pkgs: { default = devShell pkgs; });

  apps = forAllSystems (pkgs: {
    ci = {
      type = "app";
      program = lib.getExe (pkgs.writeShellApplication {
        name = "${name}-ci";
        runtimeInputs = everything pkgs ++ [ pkgs.nix ]
          ++ lib.optional pkgs.stdenv.hostPlatform.isLinux pkgs.util-linux; # flock
        # Each step is quoted whole on purpose: it expands when it runs.
        excludeShellChecks = [ "SC2016" ];
        text = ''
          cd "$(git rev-parse --show-toplevel)"
          # In CI (the runner sets CI) every job checks out into a new folder,
          # and build caches are keyed on the project's path (zig's is), so
          # every run would build from nothing. The gate runs instead in one
          # lasting checkout per repository on the runner, synced to this
          # job's commit: tracked files exactly as committed, untracked files
          # removed, the build caches kept. One job per repository uses it
          # at a time; other repositories' jobs run alongside.
          if [ -n "''${CI:-}" ] && [ -z "''${FLEET_CHECKOUT:-}" ]; then
            FLEET_CHECKOUT="''${FLEET_CACHE:-''${XDG_CACHE_HOME:-$HOME/.cache}/fleet}/${name}"
            export FLEET_CHECKOUT
            mkdir -p "$FLEET_CHECKOUT"
            if command -v flock >/dev/null; then
              exec 9>"$FLEET_CHECKOUT.lock"
              flock 9
            fi
            job=$PWD
            commit=$(git rev-parse HEAD)
            cd "$FLEET_CHECKOUT"
            [ -d .git ] || git init -q
            git fetch -q --no-tags "$job" "$commit"
            git checkout -q -f --detach "$commit"
            git clean -q -ffdx -e .zig-cache -e target -e node_modules
            echo "gate: in $FLEET_CHECKOUT at $commit (build caches kept)"
          fi
          # The steps run inside the dev shell, so they get what a person
          # gets there: the compiler environment, the SDK, the shell hooks.
          if [ -z "''${IN_NIX_SHELL:-}" ]; then
            exec nix develop .#default --command "$0" "$@"
          fi
          step() {
            echo "▶ $1"
            local rc=0
            timeout -k 30s ${stepTimeout} bash -c "$1" || rc=$?
            if [ "$rc" -eq 124 ]; then echo "✗ stopped after ${stepTimeout}: $1" >&2; fi
            [ "$rc" -eq 0 ] || exit "$rc"
          }
        '' + lib.concatMapStrings (s: "step ${lib.escapeShellArg s}\n") steps;
      });
    };
  });
}
