# Environment rules for git, enforced in every shell built from this repo.
#
#   1. No worktrees.
#   2. No branch creation with git. Branches are made in GitButler (`but`).
#   3. No AI attribution in commits. A commit is signed by the agent's own
#      persona (AGENT_PERSONA), never by a model or a tool.
#   4. No secrets pushed. Agents push without review, so every push is scanned.
#
# REAL_GIT, GITLEAKS and AI_ATTRIBUTION are set by git-guard.nix before this text.

deny() {
  echo "git: blocked by environment rule: $1" >&2
  exit 2
}

# The subcommand is the first word that is not a global option.
args=("$@")
i=0
sub=""
while [ "$i" -lt "${#args[@]}" ]; do
  case "${args[$i]}" in
    -C | -c | --git-dir | --work-tree | --namespace | --exec-path | --config-env)
      i=$((i + 2))
      ;;
    -*)
      i=$((i + 1))
      ;;
    *)
      sub="${args[$i]}"
      break
      ;;
  esac
done
globals=("${args[@]:0:$i}")
rest=("${args[@]:$((i + 1))}")

# Reads all of stdin: an early exit would break the writer's pipe and read as "clean".
has_ai_attribution() {
  grep -iE "$AI_ATTRIBUTION" >/dev/null
}

case "$sub" in
  worktree)
    # Listing and clearing leftovers stays possible; making or keeping one does not.
    case "${rest[0]:-}" in
      list | prune | remove) ;;
      *) deny "worktrees are not used here" ;;
    esac
    ;;
  checkout)
    for a in "${rest[@]}"; do
      case "$a" in
        --) break ;;
        -b | -B | --orphan | -b?* | -B?*) deny "create branches in GitButler (but), not with git checkout" ;;
      esac
    done
    ;;
  switch)
    for a in "${rest[@]}"; do
      case "$a" in
        --) break ;;
        -c | -C | --create | --force-create | --orphan | -c?* | -C?*) deny "create branches in GitButler (but), not with git switch" ;;
      esac
    done
    ;;
  branch)
    # `git branch <name>` creates one unless a flag puts it in another mode.
    mode=""
    positional=0
    for a in "${rest[@]}"; do
      case "$a" in
        -c | -C | --copy) deny "create branches in GitButler (but), not with git branch" ;;
        -d | -D | --delete | -m | -M | --move | -l | --list | --show-current | --edit-description) mode=other ;;
        -u | --set-upstream-to | --set-upstream-to=* | --unset-upstream) mode=other ;;
        --contains | --no-contains | --merged | --no-merged | --points-at) mode=other ;;
        --contains=* | --no-contains=* | --merged=* | --no-merged=* | --points-at=*) mode=other ;;
        -*) ;;
        *) positional=$((positional + 1)) ;;
      esac
    done
    if [ -z "$mode" ] && [ "$positional" -gt 0 ]; then
      deny "create branches in GitButler (but), not with git branch"
    fi
    ;;
  commit)
    for a in "${rest[@]}"; do
      if printf '%s' "$a" | has_ai_attribution; then
        deny "commit message carries AI attribution"
      fi
    done
    ;;
  push)
    # Everything not yet on a remote is what this push can publish.
    range=(HEAD --branches --not --remotes)
    unpushed="$("$REAL_GIT" "${globals[@]}" log --format=%B "${range[@]}" 2>/dev/null || true)"
    if printf '%s\n' "$unpushed" | has_ai_attribution; then
      deny "an unpushed commit carries AI attribution; reword it before pushing"
    fi
    if [ -n "$unpushed" ]; then
      root="$("$REAL_GIT" "${globals[@]}" rev-parse --show-toplevel)"
      scan=0
      PATH="$(dirname "$REAL_GIT"):$PATH" "$GITLEAKS" git "$root" \
        --no-banner --redact --exit-code 3 --log-opts="${range[*]}" >/dev/null 2>&1 || scan=$?
      case "$scan" in
        0) ;;
        3) deny "an unpushed commit contains what looks like a secret; see: gitleaks git --log-opts='${range[*]}'" ;;
        *) deny "the secret scan could not run (gitleaks exit $scan), so nothing is pushed" ;;
      esac
    fi
    ;;
esac

# An agent commits as itself.
if [ -n "${AGENT_PERSONA:-}" ]; then
  export GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME:-$AGENT_PERSONA}"
  export GIT_COMMITTER_NAME="${GIT_COMMITTER_NAME:-$AGENT_PERSONA}"
fi

exec "$REAL_GIT" "$@"
