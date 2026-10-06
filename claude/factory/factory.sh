# shellcheck shell=bash
# factory: drive the factory from a Mac, the way Claude Code sessions and a
# person do. Everything goes through the forge (forge first, local CI first);
# the factory picks up issues labelled `factory` and makes the change.
#
#   factory ticket <repo> <title> [body-file|-]   file an issue the factory takes as a ticket
#   factory status [repo]                         factory issues, open pull requests, latest CI
#   factory ci <repo> [ref]                       run the forge's CI on a branch (default main)
#   factory land <repo> <branch>                  push a branch of ~/dev/<repo> to the forge,
#                                                 open its pull request, merge when CI is green
#   factory sync <repo>                           GitHub's main into the forge's (factory-vm sync)
#   factory login                                 fetch this Mac's forge token from the VM
#
# Settings: FACTORY_FORGE (http://127.0.0.1:3300), FACTORY_ORG (lightwave-media),
# FACTORY_TOKEN_FILE (~/.config/factory/forge-token), FACTORY_ACCOUNT (claude-code).
set -euo pipefail
FORGE=${FACTORY_FORGE:-http://127.0.0.1:3300}
ORG=${FACTORY_ORG:-lightwave-media}
TOKEN_FILE=${FACTORY_TOKEN_FILE:-$HOME/.config/factory/forge-token}
ACCOUNT=${FACTORY_ACCOUNT:-claude-code}

die() { echo "factory: $*" >&2; exit 1; }
usage() { grep -E '^#   factory ' "${BASH_SOURCE[0]}" | sed 's/^# //' >&2; exit 2; }
token() { [ -s "$TOKEN_FILE" ] || die "no forge token at $TOKEN_FILE; run: factory login"; cat "$TOKEN_FILE"; }
# The token goes to curl on stdin as a header file, never as an argument.
api() { token | sed 's/^/Authorization: token /' | curl -fsS -m 60 -H @- -H 'Content-Type: application/json' "$@"; }
repo_api() { local r=$1; shift; api "$FORGE/api/v1/repos/$ORG/$r$1" "${@:2}"; }

label_id() { # <repo>: the id of the repo's `factory` label, made when missing
  local id
  id=$(repo_api "$1" "/labels?limit=50" | jq -r '[.[] | select(.name == "factory")][0].id // empty')
  [ -n "$id" ] || id=$(repo_api "$1" "/labels" -X POST -d '{"name":"factory","color":"#5319e7","description":"The factory takes this issue as a ticket"}' | jq -r .id)
  echo "$id"
}

ticket() {
  local repo=${1:?usage: factory ticket <repo> <title> [body-file|-]} title=${2:?a title} body=""
  case ${3:-} in
    "") ;;
    -) body=$(cat) ;;
    *) body=$(cat "$3") ;;
  esac
  repo_api "$repo" "/issues" -X POST \
    -d "$(jq -n --arg t "$title" --arg b "$body" --argjson l "$(label_id "$repo")" '{title: $t, body: $b, labels: [$l]}')" |
    jq -r '"filed \(.html_url)\nthe factory turns it into a ticket within a minute"'
}

repos() { # every repository of the org, or the one named
  if [ -n "${1:-}" ]; then echo "$1"; return; fi
  api "$FORGE/api/v1/orgs/$ORG/repos?limit=100" | jq -r '.[].name' | sort
}

status() {
  local r
  for r in $(repos "${1:-}"); do
    local issues prs ci
    issues=$(repo_api "$r" "/issues?state=open&type=issues&labels=factory&limit=20" | jq -r '.[] | "    issue #\(.number) \(.title)"')
    prs=$(repo_api "$r" "/pulls?state=open&limit=20" | jq -r '.[] | "    PR #\(.number) \(.title) [\(.head.ref)] by \(.user.login)"')
    ci=$(repo_api "$r" "/actions/tasks?limit=1" | jq -r '.workflow_runs[0] // empty | "\(.status) \(.name) (\(.event), \(.head_sha[0:8]))"')
    [ -n "$issues$prs" ] || [ -n "${1:-}" ] || [ "${ci%% *}" = failure ] || continue
    echo "$r: CI ${ci:-none}"
    [ -z "$issues" ] || echo "$issues"
    [ -z "$prs" ] || echo "$prs"
  done
  echo "forge: $FORGE/$ORG"
}

ci() {
  local repo=${1:?usage: factory ci <repo> [ref]} ref=${2:-main}
  repo_api "$repo" "/actions/workflows/ci.yml/dispatches" -X POST -d "$(jq -n --arg r "$ref" '{ref: $r}')" >/dev/null &&
    echo "CI queued on $repo $ref: $FORGE/$ORG/$repo/actions"
}

land() {
  local repo=${1:?usage: factory land <repo> <branch>} branch=${2:?a branch} n
  local dir=$HOME/dev/$repo
  [ -d "$dir" ] || die "no checkout at $dir"
  git -C "$dir" rev-parse --verify -q "refs/heads/$branch" >/dev/null || die "no branch $branch in $dir"
  # The repo's own pre-push hook runs; the token reaches git through its config.
  GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="http.$FORGE/.extraHeader" GIT_CONFIG_VALUE_0="Authorization: token $(token)" \
    git -C "$dir" push -q "$FORGE/$ORG/$repo.git" "refs/heads/$branch:refs/heads/$branch"
  n=$(repo_api "$repo" "/pulls?state=open&limit=50" | jq -r --arg b "$branch" '[.[] | select(.head.ref == $b)][0].number // empty')
  [ -n "$n" ] || n=$(repo_api "$repo" "/pulls" -X POST \
    -d "$(jq -n --arg b "$branch" --arg t "$(git -C "$dir" log -1 --format=%s "refs/heads/$branch")" '{head: $b, base: "main", title: $t}')" | jq -r .number)
  repo_api "$repo" "/pulls/$n/merge" -X POST -d '{"Do":"merge","merge_when_checks_succeed":true,"delete_branch_after_merge":true}' >/dev/null 2>&1 || true
  echo "$FORGE/$ORG/$repo/pulls/$n: merges itself when its CI passes"
}

login() {
  command -v factory-vm >/dev/null || die "no factory-vm on PATH"
  mkdir -p "$(dirname "$TOKEN_FILE")"
  ( umask 077; factory-vm ssh "sudo cat /var/lib/forgejo/factory-tokens/$ACCOUNT" >"$TOKEN_FILE.new" ) || true
  if [ ! -s "$TOKEN_FILE.new" ]; then
    rm -f "$TOKEN_FILE.new"
    die "the VM has no token for $ACCOUNT (forgejo/declaration.nix operators)"
  fi
  mv "$TOKEN_FILE.new" "$TOKEN_FILE"
  echo "signed in to $FORGE as $(api "$FORGE/api/v1/user" | jq -r .login)"
}

case ${1:-} in
  ticket) shift; ticket "$@" ;;
  status) shift; status "$@" ;;
  ci) shift; ci "$@" ;;
  land) shift; land "$@" ;;
  sync) shift; exec factory-vm sync "$@" ;;
  login) login ;;
  *) usage ;;
esac
