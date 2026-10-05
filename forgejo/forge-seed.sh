# Copy the declared repos from GitHub into the forge. Reads from GitHub only;
# repos already in the forge are left alone.

healthy || die "the server is not answering at $FORGE_URL"
[ -s "$auth_header" ] || die "not bootstrapped; run forge-bootstrap first"

# Private repos need a GitHub token. It goes through the environment and
# stdin, never a command line. FORGE_SEED_ANONYMOUS=1 sends none, which is
# enough for public repos.
FORGE_GH_TOKEN=""
if [ -z "${FORGE_SEED_ANONYMOUS:-}" ]; then
  FORGE_GH_TOKEN="$(gh auth token 2>/dev/null || true)"
fi
export FORGE_GH_TOKEN

failed=0
for repo in $FORGE_REPOS; do
  if api "/repos/$FORGE_ORG/$repo" >/dev/null 2>&1; then
    echo "present  $repo"
    continue
  fi
  if jq -n \
    --arg addr "https://github.com/$FORGE_GITHUB_ORG/$repo.git" \
    --arg owner "$FORGE_ORG" --arg name "$repo" \
    '{clone_addr: $addr, repo_owner: $owner, repo_name: $name, service: "github", mirror: false, private: true}
     + (if env.FORGE_GH_TOKEN != "" then {auth_token: env.FORGE_GH_TOKEN} else {} end)' |
    api /repos/migrate --data @- --max-time 1200 >/dev/null 2>&1; then
    echo "seeded   $repo"
  else
    # A failed or timed-out copy can leave an empty repo behind, which the next
    # run would mistake for a seeded one.
    api "/repos/$FORGE_ORG/$repo" --request DELETE >/dev/null 2>&1 || true
    echo "FAILED   $repo"
    failed=1
  fi
done
exit "$failed"
