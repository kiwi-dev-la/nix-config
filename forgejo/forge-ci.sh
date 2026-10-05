# The one command every repo's workflow runs, inside a Forgejo Actions job on
# a host runner: check the commit out, then run the repo's gate.

for name in GITHUB_SERVER_URL GITHUB_REPOSITORY GITHUB_SHA GITHUB_REF GITHUB_TOKEN; do
  [ -n "${!name:-}" ] || {
    echo "forge-ci: $name is not set; this command runs inside a Forgejo Actions job" >&2
    exit 1
  }
done

mkdir -p "${GITHUB_WORKSPACE:-$PWD}"
cd "${GITHUB_WORKSPACE:-$PWD}"

# The job's token reaches git through the environment, never a command line,
# and only for the forge's own address. Every branch and tag is fetched: gates
# compare against main.
(
  export GIT_CONFIG_COUNT=1
  export GIT_CONFIG_KEY_0="http.${GITHUB_SERVER_URL%/}/.extraHeader"
  export GIT_CONFIG_VALUE_0="Authorization: token $GITHUB_TOKEN"
  "$GIT" init --quiet .
  "$GIT" remote add origin "${GITHUB_SERVER_URL%/}/$GITHUB_REPOSITORY.git"
  "$GIT" fetch --quiet --tags origin '+refs/heads/*:refs/remotes/origin/*'
  "$GIT" cat-file -e "$GITHUB_SHA^{commit}" 2>/dev/null || "$GIT" fetch --quiet origin "$GITHUB_SHA"
)
case "$GITHUB_REF" in
  refs/heads/*)
    "$GIT" checkout --quiet --track "origin/${GITHUB_REF#refs/heads/}"
    "$GIT" reset --quiet --hard "$GITHUB_SHA"
    ;;
  *) "$GIT" checkout --quiet --detach "$GITHUB_SHA" ;;
esac
echo "forge-ci: $GITHUB_REPOSITORY at $("$GIT" rev-parse --short HEAD) ($GITHUB_REF)"

export CI=true

# A repo's gate is `nix run .#ci` when its flake has that app.
if [ -f flake.nix ]; then
  command -v nix >/dev/null || {
    echo "forge-ci: this repo has a flake.nix and the runner has no nix on its PATH" >&2
    exit 1
  }
  system="$(nix eval --raw --impure --expr builtins.currentSystem)"
  if nix eval --raw ".#apps.$system.ci.program" >/dev/null 2>&1; then
    echo "forge-ci: the gate is nix run .#ci"
    exec nix run .#ci
  fi
fi

# A repo that has not moved there yet has the fleet's older gate, `mise run
# ci`. It runs in the environment the repo declares: its flake's `ci` dev
# shell, else its default one. With no flake it gets only what its mise.toml
# installs and what the runner's host has.
[ -f mise.toml ] || [ -f .mise.toml ] || {
  echo "forge-ci: no gate here: neither a ci app in a flake nor a mise.toml" >&2
  exit 1
}
enter=()
if [ -f flake.nix ]; then
  for shell in ci default; do
    if nix eval --raw ".#devShells.$system.$shell.drvPath" >/dev/null 2>&1; then
      enter=(nix develop ".#$shell" --command)
      echo "forge-ci: the gate is mise run ci, in the flake's $shell shell"
      break
    fi
  done
fi
[ "${#enter[@]}" -gt 0 ] || echo "forge-ci: the gate is mise run ci, with the tools mise.toml installs and the runner's host has"

# The gate sees the repo's own mise.toml and nothing from the account the
# runner happens to run under.
export MISE_YES=1
export MISE_TRUSTED_CONFIG_PATHS="$PWD"
export MISE_GLOBAL_CONFIG_FILE="$NO_GLOBAL_CONFIG"
exec "${enter[@]}" sh -c 'mise install && exec mise run ci'
