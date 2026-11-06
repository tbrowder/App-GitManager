unit module App::GitManager::CLI;

use JSON::Fast;
use App::GitManager::Status;

my constant $USAGE = q:to/HELP/;
Usage: gitmanager status [options]
       gitmanager --help

Read-only status of one local Git repository (no network access).

Options:
  --repo=PATH          Repository path (default: current directory)
  --all                Inspect immediate Git subdirectories of --repo
  --remote=NAME        Remote to display (default: origin)
  --json               Emit structured JSON instead of text
  --verbose            Show local and remote-tracking branch names
  --dry-run            Accepted; status is already read-only
  --yes                Accepted; status never prompts
  --no-interactive     Accepted; status never prompts
  --help               Show this help

Examples:
  gitmanager status
  gitmanager status --repo=/path/to/Text-Utils
  gitmanager status --all --repo=/path/to/my-public-modules
  gitmanager status --all --json
HELP

sub print-report(%report, Bool :$verbose = False --> Nil) {
    say "Repository:       {%report<name>}";
    say "Path:             {%report<path>}";
    say "Branch:           {%report<branch>}";
    say "Remote:           {%report<remote>}";
    say "Remote URL:       {%report<remote-url> || '(none)'}";
    say "GitHub:           {%report<github> || '(not a GitHub remote)'}";
    say "Working tree:     {%report<clean> ?? 'CLEAN' !! 'CHANGED'}";
    say "Staged:           {%report<staged>}";
    say "Unstaged:         {%report<unstaged>}";
    say "Untracked:        {%report<untracked>}";
    say "Conflicts:        {%report<conflicted>}";
    say "Upstream:         {%report<upstream> || '(none)'}";
    say "Ahead (cached):   {%report<ahead> // 'unknown'}";
    say "Behind (cached):  {%report<behind> // 'unknown'}";
    say "Note: Ahead/behind counts use cached upstream refs; no fetch was run.";
    say "Note: Unborn branch (no commits)." if %report<unborn>;

    if $verbose {
        say 'Local branches:';
        for %report<local-branches>.list -> $branch {
            say "  $branch";
        }
        say 'Remote-tracking branches:';
        for %report<remote-branches>.list -> $branch {
            say "  $branch";
        }
    }
}

sub run-cli(@arguments --> Int) is export {
    my @args = @arguments;
    my $command = 'status';
    if @args and not @args[0].starts-with('--') {
        $command = @args.shift;
    }

    my $repo = '.';
    my $remote = 'origin';
    my $all = False;
    my $json = False;
    my $verbose = False;
    my $help = False;

    while @args {
        my $option = @args.shift;
        given $option {
            when '--help'           { $help = True }
            when '--all'            { $all = True }
            when '--json'           { $json = True }
            when '--verbose'        { $verbose = True }
            when '--dry-run'        { }
            when '--yes'            { }
            when '--no-interactive' { }
            when '--repo' {
                unless @args {
                    note 'Missing value for --repo';
                    return 2;
                }
                $repo = @args.shift;
            }
            when '--remote' {
                unless @args {
                    note 'Missing value for --remote';
                    return 2;
                }
                $remote = @args.shift;
            }
            default {
                if $option.starts-with('--repo=') {
                    $repo = $option.substr(7);
                }
                elsif $option.starts-with('--remote=') {
                    $remote = $option.substr(9);
                }
                else {
                    note "Unknown option: $option";
                    return 2;
                }
            }
        }
    }

    if $help or $command eq 'help' {
        print $USAGE;
        return 0;
    }
    if $command ne 'status' {
        note "Command not implemented in Phase 1: $command";
        return 2;
    }
    if not $repo.chars or not $remote.chars {
        note 'Repository and remote must be nonempty';
        return 2;
    }

    my @paths;
    my @reports;
    try {
        @paths = $all ?? repository-paths($repo).list !! ($repo,);
        CATCH {
            default {
                note .message;
                return 2;
            }
        }
    }
    unless @paths {
        note "No immediate Git repositories found under $repo";
        return 1;
    }

    my $failures = 0;
    for @paths -> $path {
        try {
            @reports.push(inspect-repo($path, :$remote));
            CATCH {
                default {
                    note "Cannot inspect $path: {.message}";
                    $failures++;
                }
            }
        }
    }

    if $json {
        say to-json({ repositories => @reports, failures => $failures });
    }
    else {
        for @reports.kv -> $index, %report {
            say() if $index > 0;
            print-report(%report, :$verbose);
        }
    }
    return $failures ?? 1 !! 0;
}
