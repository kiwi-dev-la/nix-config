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

[ -f mise.toml ] || [ -f .mise.toml ] || {
  echo "forge-ci: no mise.toml; every repo's gate is \`mise run ci\`" >&2
  exit 1
}

# The gate sees the repo's own mise.toml and nothing from the account the
# runner happens to run under.
export CI=true
export MISE_YES=1
export MISE_TRUSTED_CONFIG_PATHS="$PWD"
export MISE_GLOBAL_CONFIG_FILE="$NO_GLOBAL_CONFIG"
mise install
exec mise run ci
