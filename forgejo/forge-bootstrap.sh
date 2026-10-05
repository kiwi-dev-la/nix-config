# Bring the forge to the declared state: this host's API token, the org and
# this host's runner. Safe to run again; it only adds what is missing.
#
# Minting the token takes the password of the forge's admin, on stdin:
#   factory-vm ssh sudo cat /var/lib/forgejo/admin-password | forge-bootstrap
# Once this host holds a token the forge accepts, no password is read.

for _ in $(seq 60); do
  healthy && break
  sleep 1
done
healthy || die "the forge is not answering at $FORGE_URL"

mkdir -p "$secrets"
chmod 700 "$forge_home" "$secrets"

status=401
[ ! -s "$auth_header" ] || status="$(token_status "$auth_header")"
case "$status" in
  200) ;;
  401)
    [ ! -t 0 ] || die "this host has no token for $FORGE_URL; give the password of its admin $FORGE_ADMIN on stdin"
    password="$(cat)"
    [ -n "$password" ] || die "no password on stdin"
    # curl reads the password from a file descriptor, never a command line.
    password="${password//\\/\\\\}"
    password="${password//\"/\\\"}"
    token="$(jq -n --arg name "forge-$runner_name-$(date +%s)" '{name: $name, scopes: ["all"]}' |
      curl --fail --silent \
        --config <(printf 'user = "%s:%s"\n' "$FORGE_ADMIN" "$password") \
        --header "Content-Type: application/json" --data @- \
        "$FORGE_URL/api/v1/users/$FORGE_ADMIN/tokens" | jq -r .sha1)" ||
      die "$FORGE_URL refused the password given for $FORGE_ADMIN"
    (umask 077 && printf 'Authorization: token %s\n' "$token" >"$auth_header")
    [ "$(token_status "$auth_header")" = 200 ] || die "$FORGE_URL does not accept the token it just made for $FORGE_ADMIN"
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
