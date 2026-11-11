unit module App::GitManager::CLI;

use JSON::Fast;
use App::GitManager::Status;
use App::GitManager::Sync;
use App::GitManager::Alias;
use App::GitManager::PR;
use App::GitManager::PruneBranches;
use App::GitManager::Release;

my constant $USAGE = q:to/HELP/;
Usage: gitmanager status [options]
       gitmanager sync [options]
       gitmanager alias <add|list|show|remove> [arguments] [options]
       gitmanager pr <list|view|create|merge> [number] [options]
       gitmanager prune-branches [--base=BRANCH] [--delete] [options]
       gitmanager release <check|tag|push-tag|github> [options]
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
  --title=TEXT         PR title (create only)
  --body=TEXT          PR body (create only; default empty)
  --base=BRANCH        PR target or prune merge base
  --merge-method=NAME  Merge method: merge, squash, rebase
  --delete             Delete eligible local branches (prune only)
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
  gitmanager pr list -r tu
  gitmanager pr view 12 -r tu
  gitmanager pr create -r tu --base=master --title="Fix bug"
  gitmanager pr merge 12 -r tu --dry-run
  gitmanager prune-branches -r tu --base=master --dry-run
  gitmanager prune-branches -r tu --base=master --delete
  gitmanager release check -r gm
  gitmanager release tag -r gm --dry-run
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
    my $delete = False;
    my $title = '';
    my $body = '';
    my $base = '';
    my $merge-method = 'merge';
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
            when '--delete'         { $delete = True }
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
            when '--title' | '--body' | '--base' | '--merge-method' {
                unless @args {
                    note "Missing value for $option";
                    return 2;
                }
                my $value = @args.shift;
                given $option {
                    when '--title' { $title = $value }
                    when '--body' { $body = $value }
                    when '--base' { $base = $value }
                    when '--merge-method' { $merge-method = $value }
                }
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
                elsif $option.starts-with('--title=') {
                    $title = $option.substr(8);
                }
                elsif $option.starts-with('--body=') {
                    $body = $option.substr(7);
                }
                elsif $option.starts-with('--base=') {
                    $base = $option.substr(7);
                }
                elsif $option.starts-with('--merge-method=') {
                    $merge-method = $option.substr(15);
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
        if $delete {
            note '--delete is valid only for prune-branches';
            return 2;
        }
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
    if $command eq 'prune-branches' {
        if @positionals or $all or $push or $title.chars or $body.chars or
                $merge-method ne 'merge' or $remote ne 'origin' {
            note 'Invalid options for prune-branches';
            return 2;
        }
        my %plan;
        try {
            $repo = resolve-repo($repo);
            %plan = prune-plan($repo, :$base);
            CATCH {
                default {
                    note "Prune refused: {.message}";
                    return 1;
                }
            }
        }
        if $delete and not $dry-run and %plan<count> > 0 and not $yes {
            if $no-interactive or not $*IN.t {
                note 'Branch deletion requires confirmation or --yes';
                return 2;
            }
            say "Repository: {%plan<path>}";
            say "Base: {%plan<base>}";
            say 'Branches to delete: ' ~ %plan<candidates>.join(', ');
            print 'Delete these local branches? [y/N] ';
            my $answer = $*IN.get;
            unless $answer.defined and $answer.lc.trim eq 'y' {
                note 'Branch deletion cancelled';
                return 1;
            }
        }
        my %result = %plan;
        if $delete and not $dry-run and %plan<count> > 0 {
            try {
                %result = prune-branches($repo, :$base, :$delete);
                CATCH {
                    default {
                        note "Prune failed: {.message}";
                        return 1;
                    }
                }
            }
        }
        if $json {
            say to-json(%result);
        }
        else {
            say "Repository: {%result<path>}";
            say "Merge base: {%result<base>}";
            say "Eligible local branches: {%result<count>}";
            for %result<candidates>.list -> $branch {
                say "  $branch";
            }
            if $delete and $dry-run {
                say 'Dry run: no branches deleted.';
            }
            elsif $delete {
                say 'Deleted: ' ~ %result<deleted>.elems;
            }
            else {
                say 'Inspection only; use --delete to remove eligible branches.';
            }
        }
        return 0;
    }
    if $command eq 'release' {
        if @positionals.elems != 1 or $all or $push or $delete or
                $title.chars or $body.chars or $base.chars or
                $merge-method ne 'merge' {
            note 'Usage: gitmanager release <check|tag|push-tag|github> [options]';
            return 2;
        }
        my $action = @positionals[0];
        unless $action eq 'check' or $action eq 'tag' or
                $action eq 'push-tag' or $action eq 'github' {
            note "Unknown release action: $action";
            return 2;
        }
        my $mutating = $action ne 'check';
        my %preview;
        try {
            $repo = resolve-repo($repo);
            %preview = release-action($repo, $action, :$remote, :dry-run);
            CATCH {
                default {
                    note "Release refused: {.message}";
                    return 1;
                }
            }
        }
        if $mutating and not $dry-run and not $yes {
            if $no-interactive or not $*IN.t {
                note 'Release modification requires confirmation or --yes';
                return 2;
            }
            say "Repository: {%preview<path>}";
            say "Action: $action   Tag: {%preview<tag>}";
            print 'Proceed? [y/N] ';
            my $answer = $*IN.get;
            unless $answer.defined and $answer.lc.trim eq 'y' {
                note 'Release cancelled';
                return 1;
            }
        }
        my %result = %preview;
        unless $dry-run or $action eq 'check' {
            try {
                %result = release-action($repo, $action, :$remote);
                CATCH {
                    default {
                        note "Release failed: {.message}";
                        return 1;
                    }
                }
            }
        }
        if $json {
            say to-json(%result);
        }
        else {
            say "Repository: {%result<path>}";
            say "Version: {%result<version>}  Tag: {%result<tag>}";
            say %result<message>;
        }
        return 0;
    }
    if $command eq 'pr' {
        if $delete {
            note '--delete is valid only for prune-branches';
            return 2;
        }
        if $all or $push {
            note '--all and --push are not supported for pr';
            return 2;
        }
        my $action = @positionals.elems ?? @positionals.shift !! '';
        unless $action eq 'list' or $action eq 'view' or
                $action eq 'create' or $action eq 'merge' {
            note 'Usage: gitmanager pr <list|view|create|merge> ...';
            return 2;
        }
        my $expects-number = ($action eq 'view' or $action eq 'merge');
        if @positionals.elems != ($expects-number ?? 1 !! 0) {
            note 'Invalid PR number or extra positional arguments';
            return 2;
        }
        my $number = $expects-number ?? @positionals[0] !! '';
        if $no-interactive and not $yes and not $dry-run and
                ($action eq 'create' or $action eq 'merge') {
            note 'PR modification requires --yes in noninteractive mode';
            return 2;
        }
        if $action eq 'list' or $action eq 'view' {
            if $title.chars or $body.chars or $base.chars or
                    $merge-method ne 'merge' {
                note 'PR creation and merge options are invalid here';
                return 2;
            }
        }
        if $action eq 'create' and $merge-method ne 'merge' {
            note '--merge-method is valid only for pr merge';
            return 2;
        }
        if $action eq 'merge' and ($title.chars or $body.chars or $base.chars) {
            note '--title, --body, --base are valid only for pr create';
            return 2;
        }
        my %preview;
        try {
            $repo = resolve-repo($repo);
            %preview = pr-action($repo, $action, :$remote, :$number,
                :$title, :$body, :$base, :$merge-method, :dry-run);
            CATCH {
                default {
                    note "PR refused: {.message}";
                    return 1;
                }
            }
        }
        my $mutating = ($action eq 'create' or $action eq 'merge');
        if $mutating and not $dry-run and not $yes {
            unless $*IN.t {
                note 'PR modification requires confirmation or --yes';
                return 2;
            }
            say "Repository: {%preview<repository>}";
            say "Action: $action";
            say "PR number: $number" if $action eq 'merge';
            say "Title: $title  Base: $base" if $action eq 'create';
            print 'Proceed? [y/N] ';
            my $answer = $*IN.get;
            unless $answer.defined and $answer.lc.trim eq 'y' {
                note 'PR operation cancelled';
                return 1;
            }
        }
        my %result = %preview;
        unless $dry-run {
            try {
                %result = pr-action($repo, $action, :$remote, :$number,
                    :$title, :$body, :$base, :$merge-method);
                CATCH {
                    default {
                        note "PR failed: {.message}";
                        return 1;
                    }
                }
            }
        }
        if $json {
            say to-json(%result);
        }
        elsif $dry-run {
            say "PR $action preview: {%result<repository>}";
            say 'Command arguments: ' ~ %result<arguments>.join(' ');
            say %result<message>;
        }
        elsif $action eq 'list' or $action eq 'view' {
            say to-json(%result<data>);
        }
        else {
            say "PR $action: {%result<message>}";
        }
        return 0;
    }
    if @positionals {
        note "Unexpected arguments: {@positionals.join(' ')}";
        return 2;
    }
    if $delete {
        note '--delete is valid only for prune-branches';
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
