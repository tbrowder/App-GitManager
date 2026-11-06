TITLE
=====

App::GitManager

SYNOPSIS
========

    gitmanager status
    gitmanager status --repo=/path/to/repo
    gitmanager status --all --repo=/path/to/parent
    gitmanager status --json
    gitmanager status --verbose

DESCRIPTION
===========

Phase 1 of App::GitManager implements read-only inspection of one Git working tree. With `--all`, it examines immediate subdirectories of `--repo` that contain a `.git` entry (including linked worktrees). It does not recursively descend into nested projects.

No network requests, fetches, pulls, pushes, staging, commits, resets, branch deletion, or changes to tracked files occur.

Git's `--no-optional-locks` option is used to prevent optional index refresh writes during status inspection.

Ahead and behind counts compare HEAD to the cached upstream tracking reference. They do not establish whether the GitHub server has newer commits. An absent upstream produces unknown counts.

OPTIONS
=======

  * `--repo=PATH` Repository path or parent directory for `--all`.

  * `--all` Examine immediate repositories below the parent.

  * `--remote=NAME` Remote whose URL is displayed; default `origin`.

  * `--json` Machine-readable status report.

  * `--verbose` Include branch lists.

  * `--dry-run` Accepted; this command is already read-only.

  * `--yes` Accepted; no confirmations needed for status.

  * `--no-interactive` Accepted; status never prompts.

EXIT CODES
==========

0 for success, 1 when repositories cannot be inspected or none are found, 2 for unsupported options, commands, or invalid arguments.

ROADMAP
=======

Future phases: sync, pr, prune-branches, and release. These commands are intentionally NOT implemented in Phase 1.

