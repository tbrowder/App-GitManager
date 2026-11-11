unit module App::GitManager::PruneBranches;

use App::GitManager::Git;

# Protect traditional default and integration branches even if they are merged.
my constant @PROTECTED = <main master develop development trunk>;

sub checked(Str:D $repo, *@args --> Str) {
    my $result = run-git($repo, |@args);
    die "Git failed ({@args.join(' ')}): {$result.stderr.trim}"
        unless $result.success;
    return $result.stdout.trim;
}

sub prune-plan(Str:D $path, Str :$base = '' --> Hash) is export {
    my $root = checked($path, 'rev-parse', '--show-toplevel');
    die 'Not a working-tree repository' unless $root.chars;
    my $head = checked($root, 'symbolic-ref', '--quiet', '--short', 'HEAD');
    my $tree = checked($root, 'status', '--porcelain=v1', '-z');
    die 'Refusing to prune while the working tree is dirty'
        if $tree.chars;

    my $target = $base;
    if not $target.chars {
        my $default = run-git($root, 'symbolic-ref', '--quiet', '--short',
            'refs/remotes/origin/HEAD');
        if $default.success {
            $target = $default.stdout.trim;
        }
        else {
            die 'No remote default branch known; supply --base=BRANCH';
        }
    }
    die 'Invalid base branch' if $target.starts-with('-') or
        $target.contains(' ') or $target.contains('..') or
        $target.contains('~') or $target.contains('^') or
        $target.contains(':') or $target.contains('\\');
    checked($root, 'rev-parse', '--verify', '--quiet', $target ~ '^{commit}');

    my $merged = checked($root, 'for-each-ref', '--merged=' ~ $target,
        '--format=%(refname:short)', 'refs/heads');
    my @candidates;
    for $merged.lines -> $branch {
        next unless $branch.chars;
        next if $branch eq $head or $branch eq $target;
        next if $branch (elem) @PROTECTED;
        next if $branch.starts-with('-');
        @candidates.push($branch);
    }
    return %(
        path => $root, base => $target, branch => $head,
        candidates => @candidates.Array,
        count => @candidates.elems,
        note => 'Local branches only; no remote branches are deleted',
    );
}

sub prune-branches(Str:D $path, Str :$base = '',
    Bool :$delete = False, Bool :$dry-run = False --> Hash) is export {
    my %plan = prune-plan($path, :$base);
    %plan<dry-run> = $dry-run;
    %plan<deleted> = [];
    return %plan unless $delete and not $dry-run;

    # Recheck before *each* deletion. Git -d also refuses unmerged branches
    # and branches checked out in other worktrees.
    my @deleted;
    for %plan<candidates>.list -> $branch {
        my %current = prune-plan(%plan<path>, :base(%plan<base>));
        die "Safety conditions changed before deleting $branch"
            unless $branch (elem) %current<candidates>.list;
        my $result = run-git(%plan<path>, 'branch', '-d', '--', $branch);
        die "Cannot delete branch $branch: {$result.stderr.trim}"
            unless $result.success;
        @deleted.push($branch);
    }
    %plan<deleted> = @deleted.Array;
    return %plan;
}
