# Shared by the forge-* commands. The FORGE_* values come from default.nix.

forge_home="${FORGE_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}/forgejo}"
secrets="$forge_home/secrets"
app_ini="$forge_home/custom/conf/app.ini"
runner_name="${FORGE_RUNNER_NAME:-$(hostname -s)}"

die() {
  echo "forge: $1" >&2
  exit 1
}

# forgejo, pointed at this forge's state and config.
forge() {
  forgejo --work-path "$forge_home" --config "$app_ini" "$@"
}

# The API as the admin: api <path> [curl options]. The token is read from a
# file so it never appears in a process list.
api() {
  local path="$1"
  shift
  curl --fail --silent --show-error \
    --header "@$secrets/admin_auth_header" \
    --header "Content-Type: application/json" \
    "$@" "$FORGE_URL/api/v1$path"
}

healthy() {
  curl --fail --silent --max-time 2 "$FORGE_URL/api/healthz" >/dev/null 2>&1
}
