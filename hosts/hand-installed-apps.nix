{ lib, ... }:

let
  # Apps Nix cannot install (vendor .pkg installers, licence-walled downloads).
  # The day you install one by hand, add its exact name as it appears in
  # /Applications (without ".app").
  handInstalledApps = [
    "Safari"            # ships with macOS
    "Utilities"         # macOS folder
    "DaVinci Resolve"   # blackmagicdesign.com/support
    "BaselightLOOK"     # filmlight.ltd.uk
    "Daylight"          # filmlight.ltd.uk
    "Notion Calendar"   # notion.com/calendar
    # The nixpkgs builds of these two are months behind and cannot update
    # themselves; the vendor builds are signed and current.
    "Notion"            # notion.com/desktop
    "GitButler"         # gitbutler.com (includes the `but` command-line tool)
  ];
in
{
  # On every rebuild, name anything in /Applications that neither Nix nor the
  # list above accounts for. Reports only; never deletes.
  system.activationScripts.postActivation.text = ''
    approved=${lib.escapeShellArg (lib.concatStringsSep "\n" handInstalledApps)}
    for entry in /Applications/*; do
      name=$(basename "$entry" .app)
      [ "$name" = "Nix Apps" ] && continue
      printf '%s\n' "$approved" | grep -qxF "$name" && continue
      echo "unmanaged app: $name (add it to hosts/hand-installed-apps.nix, or uninstall it)" >&2
    done
  '';
}
