# shellcheck shell=bash
# Retire a hand-written launchd job once its nix-darwin replacement is proven.
#
#   nix run .#archive-launchd -- <old-label> <new-label>          # dry run
#   nix run .#archive-launchd -- <old-label> <new-label> --apply  # do it
#
# Order is stamp -> declaration -> verified -> archive, never the reverse. This
# script is the last step only. It refuses unless the replacement is:
#   1. owned by nix-darwin: present in the active system closure and identical
#      to the copy nix-darwin installed in ~/Library/LaunchAgents, and
#   2. proven: loaded, and either running now or last exited 0.
# The old plist is unloaded and moved (never deleted) into
# ~/.lightwave/observability/archive, the directory core's homedir.yaml
# already declares for retirement records. No new folder is created there.
#
# Interpreter and tools are pinned by the flake (writeShellApplication); the
# only host binaries used are macOS's own launchctl and plutil.

old_label=${1:?usage: archive-launchd <old-label> <new-label> [--apply]}
new_label=${2:?usage: archive-launchd <old-label> <new-label> [--apply]}
apply=${3:-}

agents="$HOME/Library/LaunchAgents"
system_agents="/run/current-system/user/Library/LaunchAgents"
archive_dir="$HOME/.lightwave/observability/archive"
domain="gui/$(id -u)"

refuse() { echo "REFUSED: $*" >&2; exit 1; }

old_plist="$agents/$old_label.plist"
new_plist="$agents/$new_label.plist"
declared="$system_agents/$new_label.plist"

[ "$old_label" != "$new_label" ] || refuse "old and new label are the same"
[ -d "$archive_dir" ] || refuse "$archive_dir does not exist; it is declared by core, not created here"
[ -f "$old_plist" ] || refuse "$old_plist does not exist"
[ -f "$declared" ] || refuse "$new_label is not declared in the active nix-darwin system ($declared missing)"
cmp -s "$declared" "$new_plist" || refuse "$new_plist differs from the nix-darwin copy; run darwin-rebuild switch first"
cmp -s "$declared" "$old_plist" && refuse "$old_plist is the nix-darwin copy itself"

status=$(/bin/launchctl print "$domain/$new_label" 2>/dev/null) || refuse "$new_label is not loaded in $domain"
if grep -q 'state = running' <<<"$status"; then
  proof="running"
elif grep -q 'last exit code = 0$' <<<"$status"; then
  proof="last exit code 0"
else
  refuse "$new_label is loaded but has neither run successfully nor is running"
fi

stamp=$(date -u +%Y%m%dT%H%M%SZ)
target="$archive_dir/launchd.$old_label.$stamp.plist"
echo "replacement $new_label: nix-darwin owned, $proof"
echo "would unload $domain/$old_label and move $old_plist -> $target"

[ "$apply" = "--apply" ] || { echo "dry run; pass --apply to archive"; exit 0; }

/bin/launchctl bootout "$domain/$old_label" 2>/dev/null || echo "note: $old_label was not loaded"
mv "$old_plist" "$target"
echo "archived $old_label -> $target"
