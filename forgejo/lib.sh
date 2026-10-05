# Shared by the forge-* commands. The FORGE_* values come from default.nix.

forge_home="${FORGE_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}/forgejo}"
secrets="$forge_home/secrets"
# This host's API token for the forge, as a curl header line.
auth_header="${FORGE_AUTH_HEADER_FILE:-$secrets/admin_auth_header}"
runner_name="${FORGE_RUNNER_NAME:-$(hostname -s)}"

die() {
  echo "forge: $1" >&2
  exit 1
}

# The API as the admin: api <path> [curl options]. The token is read from a
# file so it never appears in a process list.
api() {
  local path="$1"
  shift
  curl --fail --silent --show-error \
    --header "@$auth_header" \
    --header "Content-Type: application/json" \
    "$@" "$FORGE_URL/api/v1$path"
}

healthy() {
  curl --fail --silent --max-time 2 "$FORGE_URL/api/healthz" >/dev/null 2>&1
}

# The HTTP status the forge gives the token in <file>: 200 when it is this
# forge's, 401 when it is not.
token_status() {
  curl --silent --output /dev/null --write-out '%{http_code}' --max-time 10 \
    --header "@$1" "$FORGE_URL/api/v1/user" || true
}

# The forge's record of this host's runner, if it has one.
runner_record() {
  [ -s "$secrets/runner_id" ] && [ -s "$secrets/runner_uuid" ] && [ -s "$secrets/runner_secret" ] || return 1
  api "/admin/actions/runners/$(cat "$secrets/runner_id")" 2>/dev/null |
    jq -e --arg uuid "$(cat "$secrets/runner_uuid")" 'select(.uuid == $uuid)'
}
