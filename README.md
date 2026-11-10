[![Actions Status](https://github.com/tbrowder/App-GitManager/actions/workflows/linux.yml/badge.svg)](https://github.com/tbrowder/App-GitManager/actions) [![Actions Status](https://github.com/tbrowder/App-GitManager/actions/workflows/macos.yml/badge.svg)](https://github.com/tbrowder/App-GitManager/actions) [![Actions Status](https://github.com/tbrowder/App-GitManager/actions/workflows/windows.yml/badge.svg)](https://github.com/tbrowder/App-GitManager/actions)

TITLE
=====

App::GitManager

SYNOPSIS
========

    gitmanager status
    gitmanager status --all --repo=/path/to/parent
    gitmanager status --json
    gitmanager sync --repo=/path/to/repo --dry-run
    gitmanager sync --repo=/path/to/repo
    gitmanager sync --repo=/path/to/repo --yes
    gitmanager sync --repo=/path/to/repo --push --yes

DESCRIPTION
===========

`App::GitManager` inspects repositories and cautiously synchronizes one checked-out branch at a time with its configured upstream remote.

STATUS
======

`status` reads the working tree, branch information, and locally cached remote-tracking references. With `--all`, it examines immediate subdirectories of `--repo` that contain a `.git` entry (including linked worktrees).

It does not fetch or contact GitHub. Ahead/behind counts for `status` are based on the last locally fetched remote-tracking references.

SYNC (PHASE 2)
==============

`sync` is intentionally restricted to a single repository; `--all` is not permitted. It requires a clean working tree, an attached branch, and a configured upstream belonging to the selected remote (default `origin`).

After confirmation, `sync` fetches with `--no-tags`, reevaluates the branch, and performs `git merge --ff-only` only when the upstream is ahead and no local commits diverge. It never silently merges, rebases, resets, deletes branches, or force-pushes.

Local commits are never pushed by default. `--push` explicitly opts into a normal, non-force push to the configured upstream branch. If the remote has advanced incompatibly, Git rejects the push. Pushing is performed only after another state check.

`--dry-run` previews planned operations using cached refs without fetching, pushing, or modifying the repository. It cannot know remote changes that have not yet been fetched. `--dry-run` does not require `--yes`.

When `--yes` is omitted, `sync` prompts interactively. `--no-interactive` refuses to prompt and requires `--yes` for an actual sync. Nonterminal input also requires `--yes`.

OPTIONS
=======

  * `--repo=PATH` Repository path (or parent for status --all).

  * `--all` Inspect immediate child repositories (status only).

  * `--remote=NAME` Selected remote, default `origin`.

  * `--json` Machine-readable report.

  * `--verbose` Include branch lists in status.

  * `--dry-run` Preview sync without network or mutations.

  * `--yes` Authorize safe sync actions without confirmation.

  * `--no-interactive` Fail rather than prompt for confirmation.

  * `--push` Additionally push local commits (sync only).

  * `--help` Show usage information.

EXIT CODES
==========

0 on success, 1 on a Git error, refusal, or cancellation; 2 on invalid options or absent noninteractive authorization.

DEVELOPMENT
===========

Run `zef test .` for unit tests and `mi6 test` to include integration tests in `xt/`. Integration tests use local temporary Git repositories only.

ROADMAP
=======

Future phases: `pr`, `prune-branches`, and `release`.

