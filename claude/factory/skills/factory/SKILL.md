---
name: factory
description: Use the Lightwave factory for any change to a lightwave-media repository - file the work as a forge issue the factory turns into a ticket, check tickets, pull requests, reviews and CI, land a branch on the local forge. Use when the user asks to change, fix or build something in a lightwave-media repo, asks what the factory is doing, or mentions the forge, Forgejo, tickets, the factory, CI on the VM, or pull requests on 127.0.0.1:3300.
---

# The factory

The factory is a NixOS VM on this Mac (nix-config `machines/factory`) running a local Forgejo forge, a ticket store and workers. An issue labelled `factory` on the forge becomes a ticket; a worker (`v_developer`, Claude Code) makes the change in the repository's clone inside its Nix dev shell and opens a pull request; the forge's CI runs `nix run .#ci` on the VM; `v_staff-engineer` reviews it; it merges on approval. GitHub only receives what passed on the forge.

## The rules

- **Forge first, local CI first, local build first.** Work on lightwave-media repositories goes through the forge at http://127.0.0.1:3300/lightwave-media, not GitHub.
- **Prefer a ticket to a hand change.** File the work as an issue and let the factory do it. Change a repository by hand only when the user asks for that, and then land it on the forge (`factory land`), never straight to GitHub.
- **One environment, pinned to the hash.** Every repository's `flake.nix` builds on `nix/fleet.nix` (the fleet template, stamped from nix-config `forgejo/fleet.nix`): `nix develop` for the tools, `nix run .#ci` for the gate. The same lock serves a person, a factory worker and CI. Never add mise, Homebrew or a download at run time to a gate.
- Never bypass a repository's pre-push hook or CI. A red gate becomes a ticket.

## Commands

The `factory` command (installed by home-manager) does everything through the forge's API with this Mac's own forge token:

| Command | What it does |
|---|---|
| `factory ticket <repo> "<title>" <body-file or ->` | files an issue labelled `factory`; within a minute it is a ticket |
| `factory status [repo]` | per repository: latest CI, open factory issues, open pull requests (who opened them) |
| `factory ci <repo> [ref]` | runs the forge's CI on a branch |
| `factory land <repo> <branch>` | pushes a branch of `~/dev/<repo>` to the forge, opens its pull request, merges it when CI passes |
| `factory sync <repo>` | brings GitHub's main into the forge's (until the forge is the only source) |
| `factory-vm sync --to-github <repo>` | pushes the forge's main and tags to GitHub, fast-forward only; refuses if GitHub is ahead |
| `factory login` | fetches this Mac's forge token from the VM once |

## Writing a ticket

A worker reads only the issue. Write it so a developer with no other context can finish it:

- **What**: the change, in the repository's own terms; the files or commands involved when known.
- **Done when**: checks that can be run - usually `nix run .#ci` passes, plus what must be true afterwards.
- **Known**: anything already learned (a failing step and its first error lines, a version that differs, a step that needs credentials and must be left out).
- One repository per issue. Work across repositories is one issue in each.

## Who is who on the forge

`joel` the owner; `claude-code` Claude Code on the Mac (this session); `factory` the gate's bot (opens and merges pull requests); `v_developer` writes code; `v_staff-engineer` reviews build pull requests; `v_engineer` writes specifications; `v_cto` reviews specifications; `jev` triage.

## Where to look

- Issues, pull requests, CI: http://127.0.0.1:3300/lightwave-media/<repo> (Issues, Pull requests, Actions).
- The live view of running workers: `factory-vm watch`.
- The factory's design and the plan: lightwave-ai `factory/DESIGN.md`.
