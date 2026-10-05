# Run the Actions runner in the foreground. Jobs run on this host, as this user.

[ -s "$secrets/runner_secret" ] || die "no runner secret; run forge-bootstrap first"

runner_home="$forge_home/runner"
mkdir -p "$runner_home/work"
cd "$runner_home"

# forge-bootstrap registered the runner under an id the server takes from the
# first 16 characters of the shared secret. The runner presents the same id.
secret="$(cat "$secrets/runner_secret")"
hex="$(printf '%s' "${secret:0:16}" | od -An -tx1 | tr -d ' \n')"
uuid="${hex:0:8}-${hex:8:4}-${hex:12:4}-${hex:16:4}-${hex:20:12}"

# The declared config replaces whatever is there on every start.
(umask 077 && sed \
  -e "s|@RUNNER_HOME@|$runner_home|g" \
  -e "s|@FORGE_HOME@|$forge_home|g" \
  -e "s|@RUNNER_UUID@|$uuid|g" \
  "$FORGE_RUNNER_CONFIG" >config.yaml)

exec forgejo-runner daemon --config config.yaml
