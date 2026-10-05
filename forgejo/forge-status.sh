# The scripted health check: exits 0 only when the forge is up and bootstrapped.

healthy || die "DOWN: nothing answers at $FORGE_URL"
[ -s "$auth_header" ] && [ "$(token_status "$auth_header")" = 200 ] ||
  die "UP but this host has no token it accepts; run forge-bootstrap"

version="$(api /version | jq -r .version)"
api "/orgs/$FORGE_ORG" >/dev/null || die "UP ($version) but org $FORGE_ORG is missing; run forge-bootstrap"
repos="$(api "/orgs/$FORGE_ORG/repos?limit=50" | jq length)"
runner="$(runner_record | jq -r .status)" ||
  die "UP ($version) but this host's runner is not registered; run forge-bootstrap"

echo "forge: UP $FORGE_URL  forgejo $version  org $FORGE_ORG  repos $repos  runner $runner_name $runner"
