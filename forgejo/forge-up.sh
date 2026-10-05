# Run the Forgejo server in the foreground.

mkdir -p "$forge_home"/{data,repositories,custom/conf} "$secrets"
chmod 700 "$forge_home" "$secrets"

# Made once per machine. They live in the state directory only: never in the
# Nix store, never in this repo.
new_secret() {
  [ -s "$secrets/$1" ] || (umask 077 && forgejo generate secret "$2" >"$secrets/$1")
}
new_secret secret_key SECRET_KEY
new_secret internal_token INTERNAL_TOKEN
new_secret jwt_secret JWT_SECRET
new_secret lfs_jwt_secret LFS_JWT_SECRET

# The declared config replaces whatever is there on every start.
(umask 077 && sed "s|@FORGE_HOME@|$forge_home|g" "$FORGE_APP_INI" >"$app_ini")

exec forgejo web --work-path "$forge_home" --config "$app_ini"
