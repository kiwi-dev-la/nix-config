# Put the fleet's files (the CI workflow, nix/fleet.nix) in every declared repo
# of the forge, as commits on its default branch. Safe to run again: a repo that already carries the
# same file is left alone. `forge-workflows --check` changes nothing and exits
# non-zero if any repo differs.

healthy || die "the forge is not answering at $FORGE_URL"
[ -s "$auth_header" ] || die "not bootstrapped; run forge-bootstrap first"

check=""
[ "${1:-}" != --check ] || check=1

different=0
for repo in $FORGE_REPOS; do
  if ! info="$(api "/repos/$FORGE_ORG/$repo" 2>/dev/null)"; then
    echo "MISSING  $repo (run forge-seed)"
    different=1
    continue
  fi
  actions="$(jq -r .has_actions <<<"$info")"
  if [ "$actions" = true ] && workflow_in_place "$repo"; then
    echo "same     $repo"
    continue
  fi
  different=1
  if [ -n "$check" ]; then
    echo "DIFFERS  $repo"
    continue
  fi

  [ "$actions" = true ] ||
    jq -n '{has_actions: true}' | api "/repos/$FORGE_ORG/$repo" --request PATCH --data @- >/dev/null
  for f in $fleet_files; do
    path=${f%%=*} source=${f#*=}
    file_in_place "$repo" "$path" "$source" && continue
    # The file's current blob id, when the repo already has one at that path.
    blob="$(api "/repos/$FORGE_ORG/$repo/contents/$path" 2>/dev/null | jq -r '.sha // empty' || true)"
    jq -n --arg content "$(base64 --wrap=0 <"$source")" \
      --arg branch "$(jq -r .default_branch <<<"$info")" --arg blob "$blob" --arg path "$path" \
      '{content: $content, branch: $branch}
       + (if $blob == "" then {message: ("Add the fleet'"'"'s " + $path)}
          else {message: ("Replace " + $path + " with the fleet'"'"'s"), sha: $blob} end)' |
      api "/repos/$FORGE_ORG/$repo/contents/$path" \
        --request "$([ -n "$blob" ] && echo PUT || echo POST)" --data @- >/dev/null
  done
  echo "stamped  $repo"
done
[ -z "$check" ] || exit "$different"
