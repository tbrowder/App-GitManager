unit module App::GitManager::Sync;

use App::GitManager::Git;
use App::GitManager::Status;

# A sync is deliberately limited to the checked-out branch of one repo.
# The selected remote must be the branch's configured upstream remote.
sub sync-preflight(Str:D $path, Str :$remote = 'origin' --> Hash) is export {
    my %report = inspect-repo($path, :$remote);
    die 'Cannot sync an unborn branch' if %report<unborn>;
    die 'Cannot sync a detached HEAD' if %report<detached>;
    die 'Cannot sync a dirty working tree (including untracked files)'
        unless %report<clean>;
    die 'Cannot sync a branch without a configured upstream'
        unless %report<upstream>.chars;

    my $root = %report<path>;
    my $branch = %report<branch>;
    my $configured = run-git($root, 'config', '--get',
        "branch.$branch.remote");
    die 'Cannot determine the configured upstream remote'
        unless $configured.success;
    die "Upstream remote is '{$configured.stdout.trim}', not '$remote'"
        unless $configured.stdout.trim eq $remote;

    my $merge-ref = run-git($root, 'config', '--get',
        "branch.$branch.merge");
    die 'Cannot determine upstream branch name' unless $merge-ref.success;
    my $ref = $merge-ref.stdout.trim;
    die 'Upstream must be a single remote branch'
        unless $ref.starts-with('refs/heads/') and
            $ref.chars > 'refs/heads/'.chars;

    my $url = run-git($root, 'remote', 'get-url', $remote);
    die "Remote '$remote' does not exist" unless $url.success;

    return %(
        path      => $root,
        branch    => $branch,
        remote    => $remote,
        upstream  => %report<upstream>,
        merge-ref => $ref,
        ahead     => %report<ahead>,
        behind    => %report<behind>,
    );
}

sub sync-repo(Str:D $path, Str :$remote = 'origin',
    Bool :$dry-run = False, Bool :$push = False --> Hash) is export {
    my %plan = sync-preflight($path, :$remote);
    %plan<dry-run> = $dry-run;
    %plan<push-requested> = $push;
    %plan<fetch-performed> = False;
    %plan<fast-forward-performed> = False;
    %plan<push-performed> = False;

    # A dry run must not fetch, update refs, merge, or push.
    if $dry-run {
        %plan<message> = 'Preview only: cached ahead/behind counts; '
            ~ 'remote changes have not been fetched';
        return %plan;
    }

    my $root = %plan<path>;
    my $branch = %plan<branch>;
    my $fetch = run-git($root, 'fetch', '--no-tags', $remote);
    die "Fetch failed: {$fetch.stderr.trim}" unless $fetch.success;
    %plan<fetch-performed> = True;

    # Recheck state after fetch and before altering the current branch.
    my %after = sync-preflight($root, :$remote);
    die 'Checked-out branch changed during sync'
        unless %after<branch> eq $branch;
    die 'Upstream changed during sync'
        unless %after<upstream> eq %plan<upstream>;
    die 'Cannot sync: upstream tracking ref is unavailable'
        unless %after<ahead>.defined and %after<behind>.defined;

    if %after<ahead> > 0 and %after<behind> > 0 {
        die 'Local and upstream branches have diverged; refusing to merge or rebase';
    }

    if %after<behind> > 0 {
        my $merge = run-git($root, 'merge', '--ff-only', '--',
            %after<upstream>);
        die "Fast-forward failed: {$merge.stderr.trim}"
            unless $merge.success;
        %plan<fast-forward-performed> = True;
    }

    # Only publish with explicit --push. Use explicit refspec, never force.
    if $push {
        my %before-push = sync-preflight($root, :$remote);
        die 'Cannot push: upstream reference is unavailable'
            unless %before-push<ahead>.defined and
                %before-push<behind>.defined;
        die 'Cannot push: branch is behind its upstream'
            if %before-push<behind> > 0;
        if %before-push<ahead> > 0 {
            my $push-result = run-git($root, 'push', '--porcelain',
                $remote, "refs/heads/$branch:{%plan<merge-ref>}");
            die "Push failed: {$push-result.stderr.trim}"
                unless $push-result.success;
            %plan<push-performed> = True;
        }
    }

    my %final = sync-preflight($root, :$remote);
    %plan<ahead> = %final<ahead>;
    %plan<behind> = %final<behind>;
    %plan<message> = $push ?? 'Synchronization completed' !!
        'Fetched and fast-forwarded where necessary; no push requested';
    return %plan;
}
