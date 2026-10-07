# Merged branches are pruned from the forge every hour. A branch goes when it
# is not main, not the head of an open pull request and has no commit that
# main lacks (compare main...<branch> is empty). A branch with unmerged
# commits stays: a parked ticket may be retried from it.
{ config, pkgs, lib, ... }:
let
  forge = import ../../forgejo/declaration.nix;
  api = "http://127.0.0.1:${toString forge.port}/api/v1";
in
{
  systemd.services.forge-prune = {
    description = "Forge: delete the branches already merged into main";
    after = [ "forgejo.service" "forgejo-admin.service" ];
    path = [ pkgs.curl pkgs.jq pkgs.gnugrep ];
    serviceConfig.Type = "oneshot";
    script = ''
      token=${config.services.forgejo.stateDir}/factory-tokens/_admin
      [ -r "$token" ] || { echo "forge-prune: no admin token yet"; exit 0; }
      call() { # <method> <path>: the forge's answer; the token never reaches argv
        curl -fsS -m 30 -X "$1" -H @<(printf 'Authorization: token %s\n' "$(cat "$token")") "${api}$2"
      }
      for repo in ${lib.escapeShellArgs forge.repos}; do
        base=/repos/${forge.org}/$repo
        open=$(call GET "$base/pulls?state=open&limit=50" | jq -r '.[].head.ref') || { echo "forge-prune: $repo: cannot list pull requests"; continue; }
        page=1
        while :; do
          names=$(call GET "$base/branches?limit=50&page=$page" | jq -r '.[].name') || { echo "forge-prune: $repo: cannot list branches"; break; }
          [ -n "$names" ] || break
          while IFS= read -r b; do
            [ "$b" = main ] && continue
            printf '%s\n' "$open" | grep -qxF -- "$b" && continue
            enc=$(jq -rn --arg b "$b" '$b | @uri')
            ahead=$(call GET "$base/compare/main...$enc" | jq -r '.total_commits') || { echo "forge-prune: $repo: cannot compare $b"; continue; }
            [ "$ahead" = 0 ] || continue
            if call DELETE "$base/branches/$enc" >/dev/null; then
              echo "forge-prune: deleted ${forge.org}/$repo:$b (merged into main)"
            else
              echo "forge-prune: could not delete ${forge.org}/$repo:$b"
            fi
          done <<< "$names"
          page=$((page + 1))
        done
      done
    '';
  };
  systemd.timers.forge-prune = {
    wantedBy = [ "timers.target" ];
    timerConfig = { OnCalendar = "hourly"; Persistent = true; };
  };
}
