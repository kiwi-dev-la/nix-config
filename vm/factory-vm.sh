# shellcheck shell=bash
# factory-vm: create and run the factory, a NixOS VM on this Mac.
# QEMU_SHARE, DEBIAN_IMAGE, FLAKE and FORWARDS are set by vm/default.nix.

usage() {
  printf '%s\n' '  factory-vm up        create it if it does not exist, start it if it is stopped' >&2
  printf '%s\n' '  factory-vm status    is it running, and is the system healthy' >&2
  printf '%s\n' '  factory-vm ssh [..]  shell (or a command) in the VM as joel' >&2
  printf '%s\n' '  factory-vm switch [flake]   apply a configuration; default is the one this' >&2
  printf '%s\n' '                              command was built from, or e.g. github:kiwi-dev-la/nix-config' >&2
  printf '%s\n' '  factory-vm switch --dev <branch> [flake]   the same, with lightwave-ai taken from a local' >&2
  printf '%s\n' '                              branch (committed state) of ~/dev/lightwave-ai: an unreleased build' >&2
  printf '%s\n' '  factory-vm sync <repo>   bring GitHub main into the forge main (fast-forward, or a merge that' >&2
  printf '%s\n' '                              keeps forge-only commits); nothing is pushed to GitHub' >&2
  printf '%s\n' '  factory-vm sync --to-github <repo>   push the forge main (and tags) to the GitHub copy,' >&2
  printf '%s\n' '                              fast-forward only; refused if GitHub has commits the forge lacks' >&2
  printf '%s\n' '  factory-vm watch     the live view: the factory tmux session, read-only, in this terminal' >&2
  printf '%s\n' '  factory-vm secret set <name>   store a secret in the VM, read from stdin (never from an argument)' >&2
  printf '%s\n' '  factory-vm secret list         which secrets the VM holds (names only)' >&2
  printf '%s\n' '  factory-vm backup [--disk]  copy the forge and the tickets to the NAS; with --disk,' >&2
  printf '%s\n' '                              also the whole VM disk (the VM is stopped meanwhile)' >&2
  printf '%s\n' '  factory-vm restore <backup folder>   put the forge and the tickets back from a backup' >&2
  printf '%s\n' '  factory-vm stop      shut it down' >&2
  printf '%s\n' '  factory-vm destroy --yes    stop it and delete its disk' >&2
  printf '%s\n' '  A second VM beside the first: FACTORY_VM_STATE=<dir> FACTORY_VM_SSH_PORT=2223' >&2
  printf '%s\n' '  FACTORY_VM_FORWARDS="3301:3300" factory-vm up   (the same for every command on it)' >&2
}

STATE="${FACTORY_VM_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/factory-vm}"
KEY="${FACTORY_VM_KEY:-$HOME/.ssh/factory_ed25519}"
SSH_PORT="${FACTORY_VM_SSH_PORT:-2222}"
CPUS="${FACTORY_VM_CPUS:-8}"
MEMORY="${FACTORY_VM_MEMORY:-16G}"
DISK_SIZE="${FACTORY_VM_DISK:-200G}"
# Where backups go: a folder on the NAS share the Mac already mounts.
BACKUP_DIR="${FACTORY_BACKUP_DIR:-/Volumes/home/factory/backups}"
# Mac port:VM port pairs, reachable on the Mac at 127.0.0.1 only. Set in vm/default.nix.
read -r -a forwards <<<"${FACTORY_VM_FORWARDS:-$FORWARDS}"

ssh_opts=(-F /dev/null -p "$SSH_PORT" -i "$KEY" -o IdentitiesOnly=yes -o ConnectTimeout=5 -o LogLevel=ERROR
  -o UserKnownHostsFile="$STATE/known_hosts")

say() { printf 'factory-vm: %s\n' "$*" >&2; }
die() { say "$*"; exit 1; }

running() { [[ -f $STATE/qemu.pid ]] && kill -0 "$(<"$STATE/qemu.pid")" 2>/dev/null; }

vm_ssh() { ssh "${ssh_opts[@]}" -o StrictHostKeyChecking=yes "$@"; }

boot() {
  local net="user,id=net0,hostfwd=tcp:127.0.0.1:$SSH_PORT-:22" pair
  for pair in "${forwards[@]}"; do
    net+=",hostfwd=tcp:127.0.0.1:${pair%%:*}-:${pair##*:}"
  done
  qemu-system-aarch64 \
    -name factory -machine virt,accel=hvf -cpu host -smp "$CPUS" -m "$MEMORY" \
    -drive if=pflash,format=raw,readonly=on,file="$QEMU_SHARE/edk2-aarch64-code.fd" \
    -drive if=pflash,format=raw,file="$STATE/efi-vars.fd" \
    -drive if=none,id=root,format=qcow2,file="$STATE/disk.qcow2",discard=unmap \
    -device virtio-blk-pci,drive=root,serial=factory-root,bootindex=0 \
    -netdev "$net" \
    -device virtio-net-pci,netdev=net0 \
    -device virtio-rng-pci \
    -display none -serial file:"$STATE/console.log" \
    -pidfile "$STATE/qemu.pid" -daemonize "$@"
}

# wait_ssh <user> <seconds> [extra ssh options]
wait_ssh() {
  local user=$1 deadline=$((SECONDS + $2))
  shift 2
  until ssh "${ssh_opts[@]}" "$@" "$user@127.0.0.1" true 2>/dev/null; do
    running || die "the VM stopped; see $STATE/console.log"
    ((SECONDS < deadline)) || die "no SSH from the VM after waiting; see $STATE/console.log"
    sleep 3
  done
}

create() {
  [[ ! -e $STATE/disk.qcow2 ]] || die "a VM already exists in $STATE"
  mkdir -p "$STATE"
  chmod 700 "$STATE"
  if [[ ! -f $KEY ]]; then
    say "creating the SSH key $KEY"
    ssh-keygen -q -t ed25519 -N "" -C factory-vm -f "$KEY"
  fi
  local pubkey work
  pubkey=$(<"$KEY.pub")
  work=$(mktemp -d)

  # A stock Debian cloud image is only the way in: it boots, takes our key,
  # and nixos-anywhere replaces it with NixOS built from the flake.
  say "preparing the disk ($DISK_SIZE, grows as it fills)"
  cp "$DEBIAN_IMAGE" "$STATE/disk.qcow2"
  chmod 600 "$STATE/disk.qcow2"
  qemu-img resize -q "$STATE/disk.qcow2" "$DISK_SIZE"
  cp "$QEMU_SHARE/edk2-arm-vars.fd" "$STATE/efi-vars.fd"
  chmod 600 "$STATE/efi-vars.fd"

  mkdir "$work/seed"
  printf 'instance-id: factory-bootstrap\nlocal-hostname: factory-bootstrap\n' >"$work/seed/meta-data"
  printf '#cloud-config\nssh_authorized_keys:\n  - %s\n' "$pubkey" >"$work/seed/user-data"
  xorriso -as mkisofs -quiet -volid cidata -joliet -rock -o "$STATE/seed.iso" "$work/seed"

  say "booting the installer image"
  boot -drive if=none,id=seed,format=raw,readonly=on,file="$STATE/seed.iso" \
    -device virtio-blk-pci,drive=seed,serial=factory-seed
  local loose=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)
  wait_ssh debian 300 "${loose[@]}"

  mkdir -p "$work/files/etc/ssh/authorized_keys.d"
  printf '%s\n' "$pubkey" >"$work/files/etc/ssh/authorized_keys.d/root"
  printf '%s\n' "$pubkey" >"$work/files/etc/ssh/authorized_keys.d/joel"
  chmod -R go-w "$work/files"

  say "installing NixOS from $FLAKE (built inside the VM)"
  nixos-anywhere --flake "$FLAKE#factory" --build-on remote \
    --ssh-port "$SSH_PORT" --post-kexec-ssh-port "$SSH_PORT" -i "$KEY" --extra-files "$work/files" \
    --target-host debian@127.0.0.1

  say "waiting for NixOS to come up"
  rm -f "$STATE/known_hosts"
  sleep 10
  wait_ssh root 600 -o StrictHostKeyChecking=accept-new
  [[ $(vm_ssh root@127.0.0.1 hostname) == factory ]] || die "the VM came up, but it is not the factory system"
  rm -rf "$work"
  say "created"
}

start() {
  running && return 0
  [[ -e $STATE/disk.qcow2 ]] || die "no VM yet; run: factory-vm up"
  rm -f "$STATE/seed.iso"
  boot
  wait_ssh root 300 -o StrictHostKeyChecking=yes
}

stop() {
  running || return 0
  local pid
  pid=$(<"$STATE/qemu.pid")
  vm_ssh root@127.0.0.1 systemctl poweroff 2>/dev/null || true
  for _ in $(seq 60); do
    kill -0 "$pid" 2>/dev/null || return 0
    sleep 1
  done
  say "the VM did not shut down in 60s; stopping QEMU"
  kill "$pid"
}

status() {
  if ! running; then
    say "stopped"
    return 1
  fi
  # shellcheck disable=SC2016  # expanded in the VM, not here
  vm_ssh root@127.0.0.1 '
    echo "running: $(hostname), NixOS $(nixos-version), up $(($(cut -d. -f1 /proc/uptime) / 60)) min"
    echo "system state: $(systemctl is-system-running)"
    systemctl --failed --no-legend
  '
}

switch() {
  running || die "the VM is not running; run: factory-vm up"
  local dev="" tmp=""
  if [[ ${1:-} == --dev ]]; then dev=${2:?usage: factory-vm switch --dev <branch> [flake]}; shift 2; fi
  local ref=${1:-$FLAKE} archived
  # An unreleased build is the same configuration with one input moved: a
  # copy of the flake whose lock points lightwave-ai at the branch's commit.
  # Only committed work goes; the tag and the pin stay for proven builds.
  if [[ -n $dev ]]; then
    local repo=${LIGHTWAVE_AI_CHECKOUT:-$HOME/dev/lightwave-ai} rev
    rev=$(git -C "$repo" rev-parse --verify "refs/heads/$dev^{commit}") || die "no branch $dev in $repo"
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' RETURN
    cp -R "$(nix flake archive --json "$ref" | jq -r .path)/." "$tmp/"
    chmod -R u+w "$tmp"
    nix flake lock "$tmp" --override-input lightwave-ai "git+file://$repo?ref=refs/heads/$dev&rev=$rev" ||
      die "could not lock lightwave-ai to $dev"
    say "switching to lightwave-ai $dev (${rev:0:9}), not a tag"
    ref=$tmp
  fi
  # The flake and every input it locks go into the VM's store first, so the
  # VM evaluates and builds from its store: a private input is read here, with
  # this Mac's SSH key, and never there.
  archived=$(NIX_SSHOPTS="${ssh_opts[*]} -o StrictHostKeyChecking=yes" \
    nix flake archive --json --to "ssh-ng://root@127.0.0.1" "$ref" | jq -r .path)
  [[ -n $archived ]] || die "could not send $ref to the VM"
  vm_ssh root@127.0.0.1 nixos-rebuild switch --flake "$archived#factory"
}

# The Mac's port for the VM's forge (3300 inside), from the forwards.
forge_port() {
  local f
  for f in "${forwards[@]}"; do [[ ${f#*:} == 3300 ]] && { echo "${f%%:*}"; return; }; done
  echo 3300
}

# github_owner <repo>: who owns the repository's GitHub copy. GITHUB_ORG and
# GITHUB_SOURCES ("repo=owner ...") come from forgejo/declaration.nix.
github_owner() {
  local pair
  for pair in ${GITHUB_SOURCES:-}; do
    [[ ${pair%%=*} == "$1" ]] && { echo "${pair#*=}"; return; }
  done
  echo "${FACTORY_GITHUB_ORG:-${GITHUB_ORG:-lightwave-media}}"
}

# sync_to_github <repo>: GitHub's main becomes the forge's main, fast-forward
# only, with the forge's tags. GitHub is the distribution copy. It is reached
# over HTTPS with the Mac's gh credentials, handed to git by gh's credential
# helper, so no token is on a command line or in a file.
sync_to_github() {
  running || die "the VM is not running; run: factory-vm up"
  local repo=${1:?usage: factory-vm sync --to-github <repo>} port token
  local org=${FACTORY_FORGE_ORG:-lightwave-media} gh_org
  gh_org=$(github_owner "$repo")
  port=$(forge_port)
  token=$(vm_ssh root@127.0.0.1 cat /var/lib/forgejo/factory-tokens/_admin) || die "the VM has no forge admin token"
  (
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
    forge="http://127.0.0.1:$port/$org/$repo.git"
    github="https://github.com/$gh_org/$repo.git"
    # The git config is set per command (in git's environment, not argv).
    g() {
      env GIT_CONFIG_COUNT=3 \
        GIT_CONFIG_KEY_0="http.http://127.0.0.1:$port/.extraHeader" GIT_CONFIG_VALUE_0="Authorization: token $token" \
        GIT_CONFIG_KEY_1="credential.https://github.com.helper" GIT_CONFIG_VALUE_1="" \
        GIT_CONFIG_KEY_2="credential.https://github.com.helper" GIT_CONFIG_VALUE_2="!gh auth git-credential" \
        git -C "$work" "$@"
    }
    g init -q
    g fetch -q "$forge" "+refs/heads/main:refs/sync/forge" "+refs/tags/*:refs/tags/*" || die "could not fetch $org/$repo from the forge"
    g fetch -q "$github" "+refs/heads/main:refs/sync/github" || die "could not fetch $gh_org/$repo from GitHub"
    if ! g merge-base --is-ancestor refs/sync/github refs/sync/forge; then
      die "$gh_org/$repo: GitHub's main has commits the forge lacks; run: factory-vm sync $repo, then try again. Nothing was pushed."
    fi
    # No force: a tag that differs on GitHub is refused, not moved.
    g push -q "$github" refs/sync/forge:refs/heads/main "refs/tags/*:refs/tags/*" || die "$gh_org/$repo: GitHub refused the push"
    say "$gh_org/$repo: GitHub's main is the forge's $(g rev-parse --short refs/sync/forge)"
  )
}

# sync <repo>: the forge's main gets GitHub's main. Work merged on GitHub
# (by hand, before the factory took a repository over) would otherwise never
# reach the forge, and the factory would build on an old main. A fast-forward
# when the forge has nothing of its own; else a merge that keeps the forge's
# commits (the CI workflow stamp, the factory's merges). The other direction
# is `sync --to-github`: GitHub only receives what was proven.
sync() {
  running || die "the VM is not running; run: factory-vm up"
  local repo=${1:?usage: factory-vm sync <repo>} port token
  local org=${FACTORY_FORGE_ORG:-lightwave-media} gh_org
  gh_org=$(github_owner "$repo")
  port=$(forge_port)
  token=$(vm_ssh root@127.0.0.1 cat /var/lib/forgejo/factory-tokens/_admin) || die "the VM has no forge admin token"
  (
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
    forge="http://127.0.0.1:$port/$org/$repo.git"
    # The token reaches git through its config, for the forge's address only.
    export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="http.http://127.0.0.1:$port/.extraHeader" GIT_CONFIG_VALUE_0="Authorization: token $token"
    g() { git -C "$work" -c user.name=factory -c user.email=factory@factory.local "$@"; }
    g init -q
    g fetch -q "git@github.com:$gh_org/$repo.git" "+refs/heads/main:refs/sync/github" || die "could not fetch $gh_org/$repo from GitHub"
    g fetch -q "$forge" "+refs/heads/main:refs/sync/forge" || die "could not fetch $org/$repo from the forge"
    if g merge-base --is-ancestor refs/sync/github refs/sync/forge; then
      say "$org/$repo: the forge's main already has GitHub's main"
      exit 0
    fi
    if g merge-base --is-ancestor refs/sync/forge refs/sync/github; then
      target=refs/sync/github
      say "$org/$repo: fast-forward to GitHub's $(g rev-parse --short refs/sync/github)"
    else
      g checkout -q --detach refs/sync/forge
      g merge -q --no-edit -m "Merge GitHub's main into the forge's main" refs/sync/github ||
        die "$org/$repo: GitHub's main and the forge's conflict; merge by hand"
      target=HEAD
      say "$org/$repo: merged GitHub's $(g rev-parse --short refs/sync/github) into the forge's main"
    fi
    g push -q "$forge" "$target:refs/heads/main" || die "$org/$repo: the forge refused the push"
  )
}

# secret set <name>: the value comes in on stdin and lands in the VM as
# /home/joel/.factory-secrets/<name>, mode 600. It is never an argument, so it
# never shows in a process list or a shell history on either side.
secret() {
  running || die "the VM is not running; run: factory-vm up"
  local name=${2:-}
  case "${1:-}" in
    set)
      [[ $name =~ ^[a-z][a-z0-9-]*$ ]] || die "secret set needs a name like claude-token"
      [[ ! -t 0 ]] || die "pipe the value in: <command that prints it> | factory-vm secret set $name"
      vm_ssh joel@127.0.0.1 "umask 077 && mkdir -p ~/.factory-secrets && tr -d '\\n' >~/.factory-secrets/$name.tmp && [ -s ~/.factory-secrets/$name.tmp ] && mv ~/.factory-secrets/$name.tmp ~/.factory-secrets/$name" \
        || die "nothing was stored for $name (empty input?)"
      say "stored $name"
      ;;
    list) vm_ssh joel@127.0.0.1 'ls ~/.factory-secrets 2>/dev/null || true' ;;
    *) die "run: factory-vm secret set <name>  or  factory-vm secret list" ;;
  esac
}

# backup [--disk]: the Mac pulls the forge's data and the fleet's state out of
# the VM into one archive on the NAS, with the services stopped for the few
# seconds the archive takes, and checks the copy. --disk also copies the VM's
# disk and firmware variables, which needs the VM stopped.
# The services a backup or a restore stops, in both layouts: the module's
# units, and the transient ones of the hand-run factory (absent ones are
# skipped). The paths are those that exist in the VM.
fleet_stop='systemctl stop gitea-runner-factory forgejo factory-gate.timer factory-gate factory-nullboiler factory-nullwatch factory-nulltickets nullhub-exp nullboiler-factory 2>/dev/null || true'
# The hand-run layout's two units are transient (systemd-run) and cannot be
# started back by name: they are recreated the way the hand setup made them,
# when their programs exist. The module's units start by name.
# shellcheck disable=SC2016  # runs in the VM
fleet_start='systemctl start forgejo; systemctl start gitea-runner-factory 2>/dev/null || true
  systemctl start factory-nulltickets factory-nullwatch factory-nullboiler factory-gate.timer 2>/dev/null || true
  if [ -x /home/joel/.nullhub/bin/nullhub ] && ! systemctl is-active -q nullhub-exp; then
    systemctl reset-failed nullhub-exp 2>/dev/null || true
    systemd-run --unit=nullhub-exp --uid=joel --gid=users -p WorkingDirectory=/home/joel -p EnvironmentFile=/home/joel/.factory-env \
      -E HOME=/home/joel -E PATH=/run/current-system/sw/bin:/run/wrappers/bin:/home/joel/.factory-bin \
      /home/joel/.nullhub/bin/nullhub serve --no-open >/dev/null 2>&1 || true
  fi
  if [ -x /home/joel/factory/bin/fleet-up ] && ! systemctl is-active -q nullboiler-factory; then
    systemctl reset-failed nullboiler-factory 2>/dev/null || true
    sudo -u joel env PATH=/home/joel/.factory-bin:/run/current-system/sw/bin:/run/wrappers/bin HOME=/home/joel \
      FACTORY_HOME=/home/joel/factory FACTORY_NULLBOILER_HOME=/home/joel/factory/state/nullboiler /home/joel/factory/bin/fleet-up >/dev/null 2>&1 || true
  fi'

# shellcheck disable=SC2016  # the loop runs in the VM, not here
fleet_paths='for p in var/lib/forgejo var/lib/factory home/joel/.nullhub home/joel/factory/state home/joel/factory-hooks home/joel/.factory-pipeline; do [ -e "/$p" ] && echo "$p"; done'

# restore <backup folder>: the forge and the factory's state come back from
# a backup; the services are stopped meanwhile and started again. Secrets
# are not in a backup: place them again with `factory-vm secret set`.
restore() {
  running || die "the VM is not running; run: factory-vm up"
  local src=${1:-}
  [[ -n $src && -f $src/factory-state.tgz ]] || die "restore needs a backup folder holding factory-state.tgz"
  (cd "$src" && sha256sum -c --quiet SHA256SUMS) || die "the archive does not match its checksum"
  say "stopping the forge and the fleet for the restore"
  vm_ssh root@127.0.0.1 "$fleet_stop"
  local rc=0
  vm_ssh root@127.0.0.1 'tar -C / -xzf -' <"$src/factory-state.tgz" || rc=$?
  # shellcheck disable=SC2016  # the script runs in the VM, not here
  vm_ssh root@127.0.0.1 '
    [ -e /var/lib/forgejo ] && chown -R forgejo:forgejo /var/lib/forgejo
    for p in /var/lib/factory /home/joel/.nullhub /home/joel/factory /home/joel/factory-hooks /home/joel/.factory-pipeline; do
      [ -e "$p" ] && chown -R joel:users "$p"
    done; true'
  # A backup of the hand-run layout restored onto the module's: the tickets,
  # the traces and the run records move to /var/lib/factory, and the
  # clones, pipelines and workflow files are made again from the restored forge.
  # shellcheck disable=SC2016  # runs in the VM
  vm_ssh root@127.0.0.1 '
    [ -d /var/lib/factory ] || exit 0
    h=/home/joel/.nullhub/instances
    if [ -f $h/nulltickets/nulltickets-1/nulltickets.db ]; then
      # The rows may still sit in the write-ahead log: fold it in first, and
      # leave no stale log beside the copy.
      sqlite3 $h/nulltickets/nulltickets-1/nulltickets.db "PRAGMA wal_checkpoint(TRUNCATE);" >/dev/null
      rm -f /var/lib/factory/nulltickets/nulltickets.db-wal /var/lib/factory/nulltickets/nulltickets.db-shm
      install -o joel -g users -m 640 $h/nulltickets/nulltickets-1/nulltickets.db /var/lib/factory/nulltickets/nulltickets.db
    fi
    if [ -d $h/nullwatch/nullwatch-1/data ]; then
      rm -rf /var/lib/factory/nullwatch/data && cp -a $h/nullwatch/nullwatch-1/data /var/lib/factory/nullwatch/data && chown -R joel:users /var/lib/factory/nullwatch
    fi
    st=/home/joel/factory/state
    [ -f $st/runs.jsonl ] && install -o joel -g users -m 640 $st/runs.jsonl /var/lib/factory/runs.jsonl
    for d in logs pending; do [ -d $st/$d ] && cp -a $st/$d/. /var/lib/factory/$d/ && chown -R joel:users /var/lib/factory/$d; done
    true'
  # The runner registered with the forge this VM had before; the restored
  # forge does not know it. Without its registration file it registers again,
  # with the restored forge's runner token.
  vm_ssh root@127.0.0.1 'rm -f /var/lib/private/gitea-runner/*/.runner /var/lib/gitea-runner/*/.runner 2>/dev/null; systemctl reset-failed gitea-runner-factory 2>/dev/null; true'
  vm_ssh root@127.0.0.1 "$fleet_start"
  ((rc == 0)) || die "the restore failed (exit $rc); the services are started again"
  vm_ssh root@127.0.0.1 'systemctl list-unit-files factory-setup.service >/dev/null 2>&1 && systemctl restart factory-setup; true'

  say "restored from $src; secrets are not in a backup, place them with: factory-vm secret set <name>"
  status
}

backup() {
  running || die "the VM is not running; run: factory-vm up"
  [[ -d ${BACKUP_DIR%/*} ]] || die "the NAS share is not mounted at ${BACKUP_DIR%/*}"
  local dest tmp
  dest=$BACKUP_DIR/$(date +%Y%m%d-%H%M%S)
  mkdir -p "$dest"
  say "stopping the forge and the fleet for the archive"
  vm_ssh root@127.0.0.1 "$fleet_stop"
  local rc=0
  # Whatever exists of either layout: the module's /var/lib/factory, and the
  # hand-run factory's folders under /home/joel. Secrets are not archived.
  vm_ssh root@127.0.0.1 "$fleet_paths"' | tar -C / -czf - -T -' >"$dest/factory-state.tgz" || rc=$?
  vm_ssh root@127.0.0.1 "$fleet_start"
  ((rc == 0)) || die "the archive failed (exit $rc); the services are started again"
  tar -tzf "$dest/factory-state.tgz" >"$dest/factory-state.list" || die "the archive does not list"
  tmp=$(mktemp -d)
  grep '\.db$' "$dest/factory-state.list" | xargs tar -xzf "$dest/factory-state.tgz" -C "$tmp" || die "could not read the database copies back"
  local db ok=1
  while IFS= read -r db; do
    if [[ $(sqlite3 "$db" 'pragma integrity_check;') != ok ]]; then say "integrity check failed: ${db#"$tmp"/}"; ok=0; fi
  done < <(find "$tmp" -name '*.db')
  rm -rf "$tmp"
  ((ok)) || die "a database copy is damaged"
  (cd "$dest" && sha256sum factory-state.tgz >SHA256SUMS)
  if [[ ${1:-} == --disk ]]; then
    say "stopping the VM to copy its disk"
    stop
    cp "$STATE/disk.qcow2" "$dest/disk.qcow2"
    cp "$STATE/efi-vars.fd" "$dest/efi-vars.fd"
    start
  fi
  say "backup in $dest: $(du -sh "$dest" | cut -f1), $(wc -l <"$dest/factory-state.list") files archived, databases ok"
}

case "${1:-}" in
  up)
    if [[ ! -e $STATE/disk.qcow2 ]]; then create; else start; fi
    status
    ;;
  status) status ;;
  ssh)
    shift
    exec ssh "${ssh_opts[@]}" -o StrictHostKeyChecking=yes joel@127.0.0.1 "$@"
    ;;
  switch)
    shift
    switch "$@"
    ;;
  stop) stop ;;
  backup)
    shift
    backup "$@"
    ;;
  restore)
    shift
    restore "$@"
    ;;
  secret)
    shift
    secret "$@"
    ;;
  sync)
    shift
    if [[ ${1:-} == --to-github ]]; then
      shift
      sync_to_github "$@"
    else
      sync "$@"
    fi
    ;;
  watch)
    running || die "the VM is not running; run: factory-vm up"
    # Read-only: keys go to the Mac's terminal, nothing is typed into the VM's windows.
    exec ssh "${ssh_opts[@]}" -o StrictHostKeyChecking=yes -t joel@127.0.0.1 \
      'tmux attach -r -t factory 2>/dev/null || echo "no factory session yet; it starts with the fleet"'
    ;;
  destroy)
    [[ ${2:-} == --yes ]] || die "this deletes the VM's disk; run: factory-vm destroy --yes"
    stop
    rm -rf "$STATE"
    say "destroyed"
    ;;
  *)
    usage
    exit 2
    ;;
esac
