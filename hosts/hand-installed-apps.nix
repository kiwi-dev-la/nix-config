{ lib, config, ... }:

let
  user = config.system.primaryUser;

  # Apps Homebrew installs and updates, declared here (nix-darwin writes the
  # Brewfile and runs it on every rebuild). An app already installed by hand
  # is adopted, not installed twice. Each cask with the name it has in
  # /Applications, so the report below knows them.
  casks = {
    "adobe-creative-cloud" = "Adobe Creative Cloud";
    "claude" = "Claude";
    "codex-app" = "Codex";
    "cursor" = "Cursor";
    "docker-desktop" = "Docker";
    "elgato-wave-link" = "Elgato Wave Link";
    "figma" = "Figma";
    "google-chrome" = "Google Chrome";
    "google-drive" = "Google Drive";
    "google-earth-pro" = "Google Earth Pro";
    "insta360-studio" = "Insta360 Studio";
    "lm-studio" = "LM Studio";
    "macwhisper" = "MacWhisper";
    "post-haste" = "Post Haste";
    "qfinder-pro" = "Qfinder Pro";
    "spotify" = "Spotify";
    "whatsapp" = "WhatsApp";
    "superwhisper" = "superwhisper";
  };

  # Mac App Store apps, by their store id (`mas list`). The name is the one in
  # /Applications.
  masApps = {
    "Keynote" = 409183694;
    "Numbers" = 409203825;
    "Pages" = 409201541;
    "Xcode" = 497799835;
    "TestFlight" = 899247664;
    "Blackmagic Disk Speed Test" = 425264550;
    "Adobe Lightroom" = 1451544217;
    "HP" = 1474276998;
  };

  # Apps Nix cannot install (vendor .pkg installers with drivers, licence-
  # walled downloads, no cask). Exact names as in /Applications. Several are
  # candidates for a Nix package of their own from the vendor's download.
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
    "GitButler"         # gitbutler.com/install.sh (README step 6); also brings `but`
    # Camera, monitor and grading hardware: vendor installers with drivers.
    "AJA" "AJA Control Room" "AJA ControlPanel" "AJA Mini-Config" "AJA System Test"
    "AXSM"              # ARRI AXS media
    "Tangent"           # Tangent panels
    "Datacolor"         # calibration
    "OWC Dock Ejector"
    "QNAP JBOD Manager"
    # Film tools from the vendor, no cask.
    "Pomfort SealVerify" "Silverstack" "Silverstack Lab"
    "ShotPutPro"
    "DCP Transfer"
    "Flanders Scientific LUT Converter"
    "Final Draft 13"
    "Movie Magic"
    "ASC Manual 10TH Ed."
    "Scriptation"
    "Shot Lister.localized"   # Shot Lister 5.21 (App Store 529436218), in its own folder
    "Principles"
    "voicebox"
    "Vectorworks 2025"
    "Adobe Photoshop 2026"    # installed by Creative Cloud
    "Runbooks"                # runbooks.gruntwork.io
    "createos"                # a local build of createOS until its first tagged release is pinned here
  ];

  # Apps that are gone and stay gone: a rebuild moves any of them that is
  # back in /Applications to the Trash (recoverable until it is emptied).
  removedApps = [
    "Adobe Photoshop (Beta)" "Adobe Photoshop 2025"
    "extFS for Mac" "iLok License Manager"
    "Shot Lister 2"           # the iPad build of Shot Lister (5.0.4); 5.21 is kept
  ];

  known = lib.attrValues casks ++ lib.attrNames masApps ++ handInstalledApps;
in
{
  homebrew = {
    enable = true;
    inherit user;
    # Nothing outside this file is removed or upgraded behind your back yet:
    # Homebrew's own formulae and casks not listed here stay as they are.
    onActivation = { autoUpdate = false; upgrade = false; cleanup = "none"; };
    # `adopt`: an app already in /Applications becomes Homebrew's, not a second copy.
    extraConfig = lib.concatMapStrings (c: ''cask "${c}", args: { adopt: true }'' + "\n") (lib.attrNames casks);
    inherit masApps;
  };

  system.activationScripts.postActivation.text = ''
    # Removed apps go to the Trash.
    for name in ${lib.escapeShellArgs removedApps}; do
      app="/Applications/$name.app"
      [ -e "$app" ] || continue
      trash="/Users/${user}/.Trash/$name $(date +%Y%m%d-%H%M%S).app"
      mv "$app" "$trash" && echo "removed app: $name (in the Trash)" >&2
    done

    # On every rebuild, name anything in /Applications that neither Nix nor the
    # lists above account for. Reports only; never deletes.
    approved=${lib.escapeShellArg (lib.concatStringsSep "\n" known)}
    for entry in /Applications/*; do
      name=$(basename "$entry" .app)
      [ "$name" = "Nix Apps" ] && continue
      printf '%s\n' "$approved" | grep -qxF "$name" && continue
      echo "unmanaged app: $name (add it to hosts/hand-installed-apps.nix, or uninstall it)" >&2
    done
  '';
}
