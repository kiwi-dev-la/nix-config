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

# A repo's gate is `nix run .#ci`, and only that.
[ -f flake.nix ] || {
  echo "forge-ci: this repo has no flake.nix; its gate is the flake app apps.<system>.ci (nix run .#ci)" >&2
  exit 1
}
command -v nix >/dev/null || {
  echo "forge-ci: this repo has a flake.nix and the runner has no nix on its PATH" >&2
  exit 1
}
system="$(nix eval --raw --impure --expr builtins.currentSystem)"
nix eval --raw ".#apps.$system.ci.program" >/dev/null 2>&1 || {
  echo "forge-ci: this repo's flake has no apps.$system.ci; its gate is nix run .#ci, so add that app" >&2
  exit 1
}
echo "forge-ci: the gate is nix run .#ci"
exec nix run .#ci
