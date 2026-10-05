# Run this host's Actions runner in the foreground. Jobs run on this host, as
# this user.

[ -s "$secrets/runner_uuid" ] && [ -s "$secrets/runner_secret" ] ||
  die "this host's runner is not registered; run forge-bootstrap first"

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

exec forgejo-runner daemon --config config.yaml
