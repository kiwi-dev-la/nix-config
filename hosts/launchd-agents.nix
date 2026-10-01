{ pkgs, lw, nullhub, obs, ... }:

# The laptop's always-on and personal launchd jobs, declared here instead of
# hand-written into ~/Library/LaunchAgents (Joel, 2026-10-01: nothing persistent
# by hand; no shell wrapper picked from whatever was on PATH).
#
# Each job keeps the Label of the plist it replaces. On `darwin-rebuild switch`
# nix-darwin unloads a same-label plist and copies its own over it, so the
# switch is the swap and no two copies fight over a port or a data directory.
# Copy the old plists into the archive first (README, "Before the first
# switch"); labels that disappear are retired with `nix run .#archive-launchd`.
#
# Cron-style jobs are not here: they come from core's cron_job stamps through
# `lw cron sync`. nullhub, Prometheus and Grafana run lightwave-ai's flake
# packages instead of scripts out of a worktree.

let
  home = "/Users/joelschaeffer";
  logs = "${home}/.lightwave/observability/launchd";

  # PATH for every job: Nix first, then the Homebrew prefix this config manages.
  path = "/etc/profiles/per-user/joelschaeffer/bin:/run/current-system/sw/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin";

  service = label: args: extra: {
    serviceConfig = {
      Label = label;
      ProgramArguments = args;
      RunAtLoad = true;
      KeepAlive = true;
      EnvironmentVariables = { PATH = path; HOME = home; };
    } // extra;
  };
in
{
  launchd.user.agents = {
    # owner: v_devops. Homebrew forgejo (managed in homebrew.nix): nixpkgs'
    # forgejo-lts is marked broken on darwin.
    forgejo = service "com.lightwave.forgejo"
      [ "/opt/homebrew/bin/forgejo" "web" "--work-path" "${home}/.lightwave/forgejo" ]
      {
        WorkingDirectory = "${home}/.lightwave/forgejo";
        StandardOutPath = "${home}/.lightwave/forgejo/log/forgejo.out.log";
        StandardErrorPath = "${home}/.lightwave/forgejo/log/forgejo.err.log";
      };

    # owner: v_devops. Replaces a local "dev" build in ~/.local/bin whose
    # version could not be compared with this one (13.x).
    forgejo-runner = service "com.lightwave.forgejo-runner"
      [ "${pkgs.forgejo-runner}/bin/forgejo-runner" "daemon" "--config" "${home}/.lightwave/forgejo-runner/config.yml" ]
      {
        WorkingDirectory = "${home}/.lightwave/forgejo-runner";
        StandardOutPath = "${home}/.lightwave/forgejo-runner/runner.out.log";
        StandardErrorPath = "${home}/.lightwave/forgejo-runner/runner.err.log";
      };

    # owner: v_devops. Homebrew postgresql@17 (managed in homebrew.nix), not
    # nixpkgs: the database uses Homebrew's pgvector extension. The label stays
    # Homebrew's so `brew services` and this declaration name the same job.
    postgresql = service "homebrew.mxcl.postgresql@17"
      [ "/opt/homebrew/opt/postgresql@17/bin/postgres" "-D" "/opt/homebrew/var/postgresql@17" ]
      {
        WorkingDirectory = "/opt/homebrew";
        StandardOutPath = "/opt/homebrew/var/log/postgresql@17.log";
        StandardErrorPath = "/opt/homebrew/var/log/postgresql@17.log";
        EnvironmentVariables = { PATH = path; HOME = home; LC_ALL = "en_US.UTF-8"; };
      };

    # owner: v_devops. The token is injected by name; lw-webhook is still a
    # Python script in ~/.local/bin until lightwave-cli ships it as a binary.
    webhook = service "com.lightwave.webhook"
      [
        "${lw}/bin/lw" "config" "exec" "--only" "NULLTICKETS_API_TOKEN" "--"
        "${pkgs.python3}/bin/python3" "${home}/.local/bin/lw-webhook" "--port" "9400"
      ]
      {
        StandardOutPath = "${home}/.lightwave/observability/webhook.stdout.log";
        StandardErrorPath = "${home}/.lightwave/observability/webhook.stderr.log";
        EnvironmentVariables = {
          PATH = path;
          HOME = home;
          AWS_PROFILE = "lightwave-agent";
          NULLTICKETS_URL = "http://127.0.0.1:7700";
          NULLTICKETS_GITHUB_PIPELINE_ID = "b3103d31-e592-4e51-a3b1-3c6d3ed5e8aa";
        };
      };

    # owner: v_lightwave-ai-engineer. One hub only: the label is unchanged, so
    # the switch replaces the hand-made job; never load both. Runs from
    # ~/.nullhub, not the worktree, so the hub no longer re-stages instance
    # binaries from <cwd>/../<component>/zig-out/bin; deploys are explicit
    # copies. PATH must resolve `claude` (Max login) or the claude-cli
    # provider silently falls back to OpenRouter. Never set ANTHROPIC_API_KEY.
    nullhub = service "com.nullhub.server"
      [
        "${lw}/bin/lw" "config" "exec" "--only" "OPENROUTER_API_KEY,NULLTICKETS_API_TOKEN" "--"
        "${nullhub}/bin/nullhub" "serve" "--no-open"
      ]
      {
        WorkingDirectory = "${home}/.nullhub";
        StandardOutPath = "${logs}/nullhub.stdout.log";
        StandardErrorPath = "${logs}/nullhub.stderr.log";
        ThrottleInterval = 30;
        EnvironmentVariables = {
          PATH = "${home}/.local/bin:${home}/.local/share/mise/shims:${path}";
          HOME = home;
          AWS_PROFILE = "lightwave-agent";
        };
      };

    # owner: v_devops. 127.0.0.1:9090; state under LW_OBS_HOME's default,
    # ~/.lightwave/runtime/observability.
    prometheus = service "com.lightwave.obs.prometheus"
      [ "${obs.obs-prometheus}/bin/obs-prometheus" ]
      {
        StandardOutPath = "${logs}/obs.prometheus.stdout.log";
        StandardErrorPath = "${logs}/obs.prometheus.stderr.log";
      };

    # owner: v_devops. 127.0.0.1:3200.
    grafana = service "com.lightwave.obs.grafana"
      [ "${obs.obs-grafana}/bin/obs-grafana" ]
      {
        StandardOutPath = "${logs}/obs.grafana.stdout.log";
        StandardErrorPath = "${logs}/obs.grafana.stderr.log";
      };

    # owner: Joel. Same script, Nix-pinned bash instead of macOS's 3.2.
    whatsapp-bridge = service "com.lightwave.whatsapp-bridge"
      [ "${pkgs.bash}/bin/bash" "${home}/.lightwave/runtime/whatsapp-bridge/run.sh" ]
      {
        WorkingDirectory = "${home}/.lightwave/runtime/whatsapp-bridge";
        StandardOutPath = "${logs}/whatsapp-bridge.stdout.log";
        StandardErrorPath = "${logs}/whatsapp-bridge.stderr.log";
        ThrottleInterval = 30;
      };

    # owner: Joel. Same script, Nix-pinned bash instead of macOS's 3.2.
    sysmon = service "com.joelschaeffer.sysmon"
      [ "${pkgs.bash}/bin/bash" "${home}/scripts/sysmon-watch.sh" ]
      {
        WorkingDirectory = home;
        StandardOutPath = "${home}/Library/Logs/sysmon-stdout.log";
        StandardErrorPath = "${home}/Library/Logs/sysmon-stderr.log";
        ThrottleInterval = 10;
      };
  };
}
