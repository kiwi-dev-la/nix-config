# Bring a running server to the declared state: admin, token, org, runner
# registration. Safe to run again; it only adds what is missing.

[ -f "$app_ini" ] || die "no config at $app_ini; start the server with forge-up first"

for _ in $(seq 60); do
  healthy && break
  sleep 1
done
healthy || die "the server is not answering at $FORGE_URL"

if ! forge admin user list --admin | awk 'NR > 1 { print $2 }' | grep -x "$FORGE_ADMIN" >/dev/null; then
  forge admin user create --admin --username "$FORGE_ADMIN" \
    --email "$FORGE_ADMIN@localhost.invalid" \
    --random-password --must-change-password=false >/dev/null
  echo "created  admin $FORGE_ADMIN"
fi

if [ ! -s "$secrets/admin_auth_header" ]; then
  token="$(forge admin user generate-access-token --username "$FORGE_ADMIN" \
    --token-name "forge-bootstrap-$(date +%s)" --scopes all --raw)"
  (umask 077 && printf 'Authorization: token %s\n' "$token" >"$secrets/admin_auth_header")
  echo "created  admin token"
fi

if ! api "/orgs/$FORGE_ORG" >/dev/null 2>&1; then
  jq -n --arg org "$FORGE_ORG" '{username: $org, visibility: "private"}' |
    api /orgs --data @- >/dev/null
  echo "created  org $FORGE_ORG"
fi

[ -s "$secrets/runner_secret" ] ||
  (umask 077 && forge forgejo-cli actions generate-secret >"$secrets/runner_secret")
forge forgejo-cli actions register --secret-file "$secrets/runner_secret" \
  --name "$runner_name" --labels "$FORGE_RUNNER_LABELS" >/dev/null
echo "declared runner $runner_name ($FORGE_RUNNER_LABELS)"
