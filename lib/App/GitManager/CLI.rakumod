unit module App::GitManager::CLI;

use JSON::Fast;
use App::GitManager::Status;
use App::GitManager::Sync;
use App::GitManager::Alias;

my constant $USAGE = q:to/HELP/;
Usage: gitmanager status [options]
       gitmanager sync [options]
       gitmanager alias <add|list|show|remove> [arguments] [options]
       gitmanager --help

Status is read-only. Sync fetches and safely fast-forwards one branch.

Options:
  --repo=PATH, -r PATH Repository path or saved alias (default: .)
  --all                Inspect child repos (status only)
  --remote=NAME        Remote to display (default: origin)
  --json               Emit structured JSON instead of text
  --verbose            Show local and remote-tracking branch names
  --dry-run            Preview sync without network or repository writes
  --yes                Confirm validated sync operations automatically
  --no-interactive     Do not prompt (sync requires --yes or --dry-run)
  --push               Also push local commits (sync only; never force)
  --help               Show this help

Examples:
  gitmanager status
  gitmanager status --repo=/path/to/Text-Utils
  gitmanager status --all --repo=/path/to/my-public-modules
  gitmanager status --all --json
  gitmanager sync --repo=/path/to/Text-Utils --dry-run
  gitmanager sync --repo=/path/to/Text-Utils --yes
  gitmanager sync --repo=/path/to/Text-Utils --push --yes
  gitmanager alias add tu /path/to/Text-Utils
  gitmanager status -r tu
  gitmanager alias list
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
    if @args and not @args[0].starts-with('-') {
        $command = @args.shift;
    }

    my $repo = '.';
    my $remote = 'origin';
    my $all = False;
    my $json = False;
    my $verbose = False;
    my $help = False;
    my $dry-run = False;
    my $yes = False;
    my $no-interactive = False;
    my $push = False;
    my @positionals;

    while @args {
        my $option = @args.shift;
        given $option {
            when '--help'           { $help = True }
            when '--all'            { $all = True }
            when '--json'           { $json = True }
            when '--verbose'        { $verbose = True }
            when '--dry-run'        { $dry-run = True }
            when '--yes'            { $yes = True }
            when '--no-interactive' { $no-interactive = True }
            when '--push'           { $push = True }
            when '-r' {
                unless @args {
                    note 'Missing value for -r';
                    return 2;
                }
                $repo = @args.shift;
            }
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
                elsif $option.starts-with('-') {
                    note "Unknown option: $option";
                    return 2;
                }
                else {
                    @positionals.push($option);
                }
            }
        }
    }

    if $help or $command eq 'help' {
        print $USAGE;
        return 0;
    }
    if $command eq 'alias' {
        if @positionals.elems == 0 {
            note 'Usage: gitmanager alias <add|list|show|remove> ...';
            return 2;
        }
        my $action = @positionals.shift;
        my $expected = $action eq 'add' ?? 2
            !! ($action eq 'list' ?? 0
            !! ($action eq 'show' or $action eq 'remove' ?? 1 !! -1));
        if $expected < 0 or @positionals.elems != $expected {
            note "Invalid alias action or arguments: $action";
            return 2;
        }
        if $all or $push or $remote ne 'origin' or $repo ne '.' {
            note 'Repository, remote, --all, and --push are not alias options';
            return 2;
        }
        my %result;
        try {
            given $action {
                when 'list' {
                    my %aliases = read-aliases();
                    %result = { action => 'list', aliases => %aliases };
                }
                when 'show' {
                    my %aliases = read-aliases();
                    die "Unknown alias: {@positionals[0]}"
                        unless %aliases{@positionals[0]}:exists;
                    %result = { action => 'show',
                        name => @positionals[0],
                        path => %aliases{@positionals[0]} };
                }
                default {
                    unless $dry-run or $yes {
                        die 'Confirmation required; pass --yes in automation'
                            if $no-interactive or not $*IN.t;
                        print "Alias $action {@positionals[0]}? [y/N] ";
                        my $answer = $*IN.get;
                        die 'Cancelled' unless $answer.defined
                            and $answer.lc.trim eq 'y';
                    }
                    %result = $action eq 'add'
                        ?? add-alias(@positionals[0], @positionals[1], :$dry-run)
                        !! remove-alias(@positionals[0], :$dry-run);
                }
            }
            CATCH {
                default {
                    note "Alias error: {.message}";
                    return 1;
                }
            }
        }
        if $json {
            say to-json(%result);
        }
        elsif $action eq 'list' {
            for %result<aliases>.keys.sort -> $name {
                say "$name  {%result<aliases>{$name}}";
            }
        }
        else {
            say "$action: {%result<name>} => {%result<path>}"
                ~ ((%result<dry-run> // False) ?? ' (dry run)' !! '');
        }
        return 0;
    }
    if @positionals {
        note "Unexpected arguments: {@positionals.join(' ')}";
        return 2;
    }
    unless $command eq 'status' or $command eq 'sync' {
        note "Command not implemented: $command";
        return 2;
    }
    if not $repo.chars or not $remote.chars or $remote.starts-with('-') {
        note 'Repository and remote must be nonempty';
        return 2;
    }

    try {
        $repo = resolve-repo($repo);
        CATCH {
            default {
                note .message;
                return 2;
            }
        }
    }

    if $command eq 'status' and $push {
        note '--push is valid only for sync';
        return 2;
    }
    if $command eq 'sync' {
        if $all {
            note '--all is not supported for sync; select one repository';
            return 2;
        }
        my %plan;
        try {
            %plan = sync-preflight($repo, :$remote);
            CATCH {
                default {
                    note "Sync refused: {.message}";
                    return 1;
                }
            }
        }
        if $dry-run {
            my %preview;
            try {
                %preview = sync-repo($repo, :$remote, :$dry-run, :$push);
                CATCH {
                    default {
                        note "Sync preview failed: {.message}";
                        return 1;
                    }
                }
            }
            if $json {
                say to-json(%preview);
            }
            else {
                say "Dry run: {%preview<path>} ({%preview<branch>})";
                say "Upstream: {%preview<upstream>}";
                say 'Cached ahead/behind: '
                    ~ "{%preview<ahead> // 'unknown'}/"
                    ~ "{%preview<behind> // 'unknown'}";
                say 'Would fetch from remote, fast-forward if possible, '
                    ~ ($push ?? 'then push if ahead.' !! 'without pushing.');
                say 'No network requests or changes made.';
            }
            return 0;
        }
        unless $yes {
            if $no-interactive or not $*IN.t {
                note 'Sync requires confirmation; pass --yes for automation';
                return 2;
            }
            say "Repository: {%plan<path>}";
            say "Branch: {%plan<branch>}  Upstream: {%plan<upstream>}";
            say 'Action: fetch, fast-forward if possible'
                ~ ($push ?? ', and push local commits' !! ' (no push)');
            print 'Proceed? [y/N] ';
            my $answer = $*IN.get;
            unless $answer.defined and $answer.lc.trim eq 'y' {
                note 'Sync cancelled';
                return 1;
            }
        }
        my %result;
        try {
            %result = sync-repo($repo, :$remote, :$push);
            CATCH {
                default {
                    note "Sync failed: {.message}";
                    return 1;
                }
            }
        }
        if $json {
            say to-json(%result);
        }
        else {
            say %result<message>;
            say "Branch: {%result<branch>}";
            say "Ahead: {%result<ahead>}  Behind: {%result<behind>}";
            say "Fast-forward: {%result<fast-forward-performed> ?? 'yes' !! 'no'}";
            say "Push: {%result<push-performed> ?? 'yes' !! 'no'}";
        }
        return 0;
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
