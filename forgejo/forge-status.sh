# The scripted health check: exits 0 only when the forge is up and bootstrapped.

healthy || die "DOWN: nothing answers at $FORGE_URL"
[ -s "$secrets/admin_auth_header" ] || die "UP but not bootstrapped; run forge-bootstrap"

version="$(api /version | jq -r .version)"
api "/orgs/$FORGE_ORG" >/dev/null || die "UP ($version) but org $FORGE_ORG is missing; run forge-bootstrap"
repos="$(api "/orgs/$FORGE_ORG/repos?limit=50" | jq length)"

echo "forge: UP $FORGE_URL  forgejo $version  org $FORGE_ORG  repos $repos"
