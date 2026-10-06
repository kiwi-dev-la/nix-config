# shellcheck shell=bash
# factory-prove: use the running factory the way a person would, and fail if
# anything does not work. Run on the Mac. It leaves one repository behind in
# Forgejo, named prove-<time>, as the record of the run.

FORGE=http://127.0.0.1:3300
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
name="prove-$(date +%Y%m%d-%H%M%S)"

step() { printf '%-52s' "$1" >&2; }
ok() { printf 'ok  %s\n' "${1:-}" >&2; }
fail() { printf 'FAILED  %s\n' "$*" >&2; exit 1; }

step "VM is running and healthy"
state=$(factory-vm ssh systemctl is-system-running) || fail "systemd reports: $state"
started=$(factory-vm ssh date +%s) # the VM's clock; the log check below starts here
ok "$state"

step "Forgejo answers its health check"
[[ $(curl -fsS -m 10 "$FORGE/api/healthz" | jq -r .status) == pass ]] || fail "$FORGE/api/healthz"
ok

# The admin password never leaves this process: it goes into a private netrc.
password=$(factory-vm ssh sudo cat /var/lib/forgejo/admin-password)
printf 'machine 127.0.0.1\nlogin joel\npassword %s\n' "$password" >"$work/netrc"
chmod 600 "$work/netrc"
api() { curl -fsS -m 20 --netrc-file "$work/netrc" -H 'Content-Type: application/json' "$@"; }
git_forge() {
  git -c credential.helper= \
    -c "credential.helper=!f() { echo username=joel; sed -n 's/^password /password=/p' '$work/netrc'; }; f" "$@"
}

step "API accepts the admin login"
[[ $(api "$FORGE/api/v1/user" | jq -r .login) == joel ]] || fail "login as joel"
ok

step "Create a repository"
api -X POST "$FORGE/api/v1/user/repos" \
  -d "{\"name\":\"$name\",\"private\":true,\"default_branch\":\"main\"}" >/dev/null || fail "create $name"
ok "joel/$name"

step "Push a commit from the Mac"
git init -q -b main "$work/src"
printf 'Pushed by factory-prove at %s\n' "$(date)" >"$work/src/README.md"
mkdir -p "$work/src/.forgejo/workflows"
cat >"$work/src/.forgejo/workflows/build.yml" <<'YAML'
on:
  push:
    branches: [main]
jobs:
  build:
    runs-on: native
    steps:
      - name: Get the code that was just pushed
        run: |
          git clone --quiet "http://token:${{ github.token }}@127.0.0.1:3300/${{ github.repository }}.git" src
          git -C src checkout --quiet "${{ github.sha }}"
      - name: Build with Nix
        run: |
          cd src
          nix build --impure --print-out-paths --expr \
            'derivation { name = "prove"; system = builtins.currentSystem; builder = "/bin/sh"; args = [ "-c" "echo built > $out" ]; src = ./README.md; }'
YAML
git -C "$work/src" add README.md .forgejo
git -C "$work/src" -c user.name=joel -c user.email=joel@factory.local commit -q -m "First commit"
git_forge -C "$work/src" push -q "$FORGE/joel/$name.git" main || fail "git push"
for _ in $(seq 30); do # Forgejo records the push a moment after accepting it
  [[ $(api "$FORGE/api/v1/repos/joel/$name" | jq -r .empty) == false ]] && break
  sleep 1
done
ok

step "Clone it back and compare"
git_forge clone -q "$FORGE/joel/$name.git" "$work/back" || fail "git clone"
cmp -s "$work/src/README.md" "$work/back/README.md" || fail "the clone differs from what was pushed"
ok

step "Open an issue"
issue=$(api -X POST "$FORGE/api/v1/repos/joel/$name/issues" \
  -d '{"title":"factory-prove","body":"Opened through the API."}' | jq -r .number) || fail "create issue"
ok "#$issue"

step "Open a pull request and merge it"
printf 'A change.\n' >>"$work/src/README.md"
git -C "$work/src" -c user.name=joel -c user.email=joel@factory.local commit -q -am "A change"
git_forge -C "$work/src" push -q "$FORGE/joel/$name.git" HEAD:refs/heads/change || fail "push the branch"
pr=$(api -X POST "$FORGE/api/v1/repos/joel/$name/pulls" \
  -d "{\"head\":\"change\",\"base\":\"main\",\"title\":\"A change\",\"body\":\"Closes #$issue\"}" | jq -r .number) || fail "open the pull request"
merged=false
for _ in $(seq 20); do
  if api -X POST "$FORGE/api/v1/repos/joel/$name/pulls/$pr/merge" -d '{"Do":"merge"}' >/dev/null 2>&1; then
    merged=true
    break
  fi
  sleep 2 # Forgejo is still working out whether the branch can be merged
done
$merged || fail "merge pull request #$pr"
ok "#$pr merged"

step "The merge closed the issue"
closed=false
for _ in $(seq 15); do
  if [[ $(api "$FORGE/api/v1/repos/joel/$name/issues/$issue" | jq -r .state) == closed ]]; then
    closed=true
    break
  fi
  sleep 2
done
$closed || fail "issue #$issue is still open"
ok

step "The merge to main started a build, and it passed"
build=pending
for _ in $(seq 60); do
  build=$(api "$FORGE/api/v1/repos/joel/$name/commits/main/status" | jq -r '.state // "pending"')
  [[ $build == pending || -z $build ]] || break
  sleep 3
done
[[ $build == success ]] || fail "build state on main: $build (see $FORGE/joel/$name/actions)"
ok

step "No errors in Forgejo's log during this run"
errors=$(factory-vm ssh "sudo journalctl -u forgejo --since @$started -p err --no-pager -q | wc -l")
[[ $errors == 0 ]] || fail "$errors error lines: factory-vm ssh sudo journalctl -u forgejo -p err --since @$started"
ok

printf '\nAll steps passed. See %s/joel/%s\n' "$FORGE" "$name" >&2
