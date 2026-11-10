unit module App::GitManager::PR;

use JSON::Fast;
use App::GitManager::Status;

# GitHub operations use the gh executable directly, never a shell.
# PR creation does not push commits and PR merging does not delete branches.
sub run-gh(*@args --> Hash) {
    my $proc = run 'gh', |@args, :out, :err;
    my $stdout = $proc.out.slurp(:close);
    my $stderr = $proc.err.slurp(:close);
    return %(success => $proc.exitcode == 0,
        stdout => $stdout, stderr => $stderr);
}

sub pr-repository(Str:D $path, Str :$remote = 'origin' --> Hash)
    is export {
    my %report = inspect-repo($path, :$remote);
    die "Remote '$remote' is not a recognized GitHub repository"
        unless %report<github>.chars;
    return %report;
}

sub pr-action(
    Str:D $path,
    Str:D $action,
    Str :$remote = 'origin',
    Str :$number = '',
    Str :$title = '',
    Str :$body = '',
    Str :$base = '',
    Str :$merge-method = 'merge',
    Bool :$dry-run = False,
    --> Hash
) is export {
    die "Unknown PR action '$action'"
        unless $action eq 'list' or $action eq 'view' or
            $action eq 'create' or $action eq 'merge';
    my %repo = pr-repository($path, :$remote);
    my $slug = %repo<github>;
    my @args = 'pr', $action, '--repo', $slug;
    my $mutating = ($action eq 'create' or $action eq 'merge');

    if $action eq 'view' or $action eq 'merge' {
        die 'A positive numeric PR number is required'
            unless $number ~~ /^ <[1..9]> \d* $/;
        @args.push($number);
    }
    if $action eq 'create' {
        die 'Cannot create a PR from a detached or unborn branch'
            if %repo<detached> or %repo<unborn>;
        die 'A nonempty PR title is required' unless $title.trim.chars;
        die 'An explicit base branch is required' unless $base.trim.chars;
        die 'Invalid base branch' if $base.starts-with('-') or
            $base.contains(' ') or $base.contains('..') or
            $base.contains('~') or $base.contains('^') or
            $base.contains(':') or $base.contains('\\');
        @args.append('--base', $base, '--head', %repo<branch>,
            '--title', $title, '--body', $body);
    }
    if $action eq 'merge' {
        die 'Merge method must be merge, squash, or rebase'
            unless $merge-method eq 'merge' or
                $merge-method eq 'squash' or $merge-method eq 'rebase';
        @args.push('--' ~ $merge-method);
    }
    if $action eq 'list' {
        @args.append('--state', 'open', '--limit', '30', '--json',
            'number,title,state,headRefName,baseRefName,url');
    }
    if $action eq 'view' {
        @args.append('--json',
            'number,title,state,headRefName,baseRefName,url,mergeable');
    }

    my %result = %(
        action => $action, repository => $slug,
        path => %repo<path>, dry-run => $dry-run,
        mutating => $mutating, arguments => @args.Array,
    );
    if $dry-run {
        %result<message> = $mutating
            ?? 'Preview only; no GitHub request or repository write made'
            !! 'Preview only; no GitHub request made';
        return %result;
    }

    # --repo selects the intended GitHub repository independently of cwd.
    my %execution = run-gh(|@args);
    die "GitHub CLI failed: {%execution<stderr>.trim || %execution<stdout>.trim}"
        unless %execution<success>;
    if $action eq 'list' or $action eq 'view' {
        %result<data> = from-json(%execution<stdout>);
    }
    else {
        %result<message> = %execution<stdout>.trim;
    }
    return %result;
}
