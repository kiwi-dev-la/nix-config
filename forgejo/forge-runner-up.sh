# Run this host's Actions runner in the foreground. Jobs run on this host, as
# this user.

[ -s "$secrets/runner_uuid" ] && [ -s "$secrets/runner_secret" ] ||
  die "this host's runner is not registered; run forge-bootstrap first"

# The runner gives up at once when the forge is not there, and the forge can
# come up after this host does.
if ! healthy; then
  echo "forge: waiting for the forge at $FORGE_URL" >&2
  until healthy; do sleep 5; done
fi

runner_home="$forge_home/runner"
mkdir -p "$runner_home/work"
cd "$runner_home"

# The declared config replaces whatever is there on every start.
(umask 077 && sed \
  -e "s|@RUNNER_HOME@|$runner_home|g" \
  -e "s|@FORGE_HOME@|$forge_home|g" \
  -e "s|@FORGE_URL@|$FORGE_URL|g" \
  -e "s|@RUNNER_UUID@|$(cat "$secrets/runner_uuid")|g" \
  "$FORGE_RUNNER_CONFIG" >config.yaml)

# Jobs get the PATH this command was started with, plus forge-ci. They do not
# get the tools this script itself uses: GNU sed ahead of the system's own
# would change what a gate runs.
runner="$(command -v forgejo-runner)"
exec env PATH="$FORGE_CI_BIN:${PATH#"$FORGE_TOOL_PATH:"}" "$runner" daemon --config config.yaml
