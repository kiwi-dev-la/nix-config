# Bring a running forge to the declared state: this host's API token, the org
# and this host's runner. Safe to run again; it only adds what is missing.
#
# Minting the token takes an admin. When this host serves the forge (forge-up)
# the admin is made here. For a forge served elsewhere, name one of its admins
# and a file holding that admin's password:
#   FORGE_ADMIN=<name> FORGE_ADMIN_PASSWORD_FILE=<file> forge-bootstrap

for _ in $(seq 60); do
  healthy && break
  sleep 1
done
healthy || die "the server is not answering at $FORGE_URL"

mkdir -p "$secrets"
chmod 700 "$forge_home" "$secrets"

status=401
[ ! -s "$auth_header" ] || status="$(token_status "$auth_header")"
case "$status" in
  200) ;;
  401)
    token_name="forge-$runner_name-$(date +%s)"
    if [ -n "${FORGE_ADMIN_PASSWORD_FILE:-}" ]; then
      [ -r "$FORGE_ADMIN_PASSWORD_FILE" ] || die "cannot read $FORGE_ADMIN_PASSWORD_FILE"
      # curl reads the password from a file descriptor, never a command line.
      password="$(cat "$FORGE_ADMIN_PASSWORD_FILE")"
      password="${password//\\/\\\\}"
      password="${password//\"/\\\"}"
      token="$(jq -n --arg name "$token_name" '{name: $name, scopes: ["all"]}' |
        curl --fail --silent --show-error \
          --config <(printf 'user = "%s:%s"\n' "$FORGE_ADMIN" "$password") \
          --header "Content-Type: application/json" --data @- \
          "$FORGE_URL/api/v1/users/$FORGE_ADMIN/tokens" | jq -r .sha1)"
    elif [ -f "$app_ini" ]; then
      if ! forge admin user list --admin | awk 'NR > 1 { print $2 }' | grep -x "$FORGE_ADMIN" >/dev/null; then
        forge admin user create --admin --username "$FORGE_ADMIN" \
          --email "$FORGE_ADMIN@localhost.invalid" \
          --random-password --must-change-password=false >/dev/null
        echo "created  admin $FORGE_ADMIN"
      fi
      token="$(forge admin user generate-access-token --username "$FORGE_ADMIN" \
        --token-name "$token_name" --scopes all --raw)"
    else
      die "this host does not serve the forge at $FORGE_URL; set FORGE_ADMIN and FORGE_ADMIN_PASSWORD_FILE to one of its admins"
    fi
    (umask 077 && printf 'Authorization: token %s\n' "$token" >"$auth_header.new")
    if [ "$(token_status "$auth_header.new")" != 200 ]; then
      rm -f "$auth_header.new"
      die "$FORGE_URL does not accept the token just made for $FORGE_ADMIN; if another host serves that forge, set FORGE_ADMIN and FORGE_ADMIN_PASSWORD_FILE"
    fi
    mv "$auth_header.new" "$auth_header"
    echo "created  token for $FORGE_ADMIN"
    ;;
  *) die "unexpected answer ($status) from $FORGE_URL when checking this host's token" ;;
esac

if ! api "/orgs/$FORGE_ORG" >/dev/null 2>&1; then
  jq -n --arg org "$FORGE_ORG" '{username: $org, visibility: "private"}' |
    api /orgs --data @- >/dev/null
  echo "created  org $FORGE_ORG"
fi

# The forge hands back the id and secret this host's runner connects with.
# The runner reports its own labels when it starts.
if ! runner_record >/dev/null; then
  registration="$(jq -n --arg name "$runner_name" '{name: $name}' |
    api /admin/actions/runners --data @-)"
  (umask 077 &&
    jq -r .id <<<"$registration" >"$secrets/runner_id" &&
    jq -r .uuid <<<"$registration" >"$secrets/runner_uuid" &&
    jq -r .token <<<"$registration" >"$secrets/runner_secret")
  echo "registered runner $runner_name"
fi
