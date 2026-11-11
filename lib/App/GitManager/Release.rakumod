unit module App::GitManager::Release;

use JSON::Fast;
use App::GitManager::Git;
use App::GitManager::Status;

sub checked(Str:D $repo, *@args --> Str) {
    my $result = run-git($repo, |@args);
    die "Git failed ({@args.join(' ')}): {$result.stderr.trim}"
        unless $result.success;
    return $result.stdout.trim;
}

sub command(Str:D $cwd, Str:D $program, *@args --> Hash) {
    my $proc = run $program, |@args, :cwd($cwd.IO), :out, :err;
    my $stdout = $proc.out.slurp(:close);
    my $stderr = $proc.err.slurp(:close);
    return %(ok => $proc.exitcode == 0, stdout => $stdout,
        stderr => $stderr, exit-code => $proc.exitcode);
}

# Read only; no fetch, test, tag, push, or GitHub API calls.
sub release-plan(Str:D $path, Str :$remote = 'origin' --> Hash)
    is export {
    my $root = checked($path, 'rev-parse', '--show-toplevel');
    die 'Not a repository working tree' unless $root.chars;
    die 'Remote name must not begin with a dash'
        if not $remote.chars or $remote.starts-with('-');
    my $meta-path = $root.IO.add('META6.json');
    die 'META6.json not found at repository root' unless $meta-path.f;
    my %meta = from-json($meta-path.slurp);
    my $version = (%meta<version> // '').Str.trim;
    die 'META6.json version must contain only digits, letters, dots or hyphens'
        unless $version ~~ /^ <[0..9]> <[A..Za..z0..9._-]>* $/;
    my $tag = $version;
    my $branch = checked($root, 'symbolic-ref', '--quiet', '--short', 'HEAD');
    die 'Cannot release with a dirty working tree'
        if checked($root, 'status', '--porcelain=v1', '--untracked-files=all').chars;
    my $head = checked($root, 'rev-parse', '--verify', 'HEAD');
    my $upstream = checked($root, 'rev-parse', '--abbrev-ref',
        '--symbolic-full-name', '@{upstream}');
    die 'Upstream is not on the selected remote'
        unless $upstream.starts-with($remote ~ '/');
    my $counts = checked($root, 'rev-list', '--left-right', '--count',
        $upstream ~ '...HEAD');
    my @counts = $counts.words;
    die 'Cannot release when local branch differs from cached upstream'
        unless @counts.elems == 2 and @counts[0] eq '0'
            and @counts[1] eq '0';
    my $remote-url = checked($root, 'remote', 'get-url', $remote);
    die 'Missing remote URL' unless $remote-url.chars;
    my $existing = run-git($root, 'rev-parse', '--verify', '--quiet',
        'refs/tags/' ~ $tag);
    my %report = inspect-repo($root, :$remote);
    return %(
        path => $root, branch => $branch, upstream => $upstream,
        remote => $remote, remote-url => $remote-url,
        github => (%report<github> // ''),
        version => $version, tag => $tag, head => $head,
        tag-exists => $existing.success,
    );
}

sub release-action(Str:D $path, Str:D $action,
    Str :$remote = 'origin', Bool :$dry-run = False --> Hash)
    is export {
    die "Unknown release action: $action"
        unless $action eq 'check' or $action eq 'tag' or
            $action eq 'push-tag' or $action eq 'github';
    my %plan = release-plan($path, :$remote);
    %plan<action> = $action;
    %plan<dry-run> = $dry-run;
    if $action eq 'tag' {
        die "Tag {%plan<tag>} already exists" if %plan<tag-exists>;
    }
    elsif $action eq 'push-tag' or $action eq 'github' {
        die "Tag {%plan<tag>} does not exist locally"
            unless %plan<tag-exists>;
        my $commit = checked(%plan<path>, 'rev-list', '-n', '1',
            'refs/tags/' ~ %plan<tag>);
        die 'Tag does not point to the current commit'
            unless $commit eq %plan<head>;
    }
    if $action eq 'github' {
        die 'A GitHub remote is required' unless %plan<github>.chars;
    }
    my @args;
    my $program = '';
    given $action {
        when 'tag' {
            $program = 'git';
            @args = ('-C', %plan<path>, 'tag', '-a', %plan<tag>,
                '-m', 'Release ' ~ %plan<tag>);
        }
        when 'push-tag' {
            $program = 'git';
            @args = ('-C', %plan<path>, 'push', %plan<remote>,
                'refs/tags/' ~ %plan<tag> ~ ':refs/tags/' ~ %plan<tag>);
        }
        when 'github' {
            $program = 'gh';
            @args = ('release', 'create', %plan<tag>, '--repo',
                %plan<github>, '--verify-tag', '--generate-notes');
        }
    }
    %plan<program> = $program;
    %plan<arguments> = @args.Array;
    if $dry-run or $action eq 'check' {
        %plan<message> = $action eq 'check'
            ?? 'Release preflight passed (cached upstream comparison)'
            !! 'Preview only; no tests, tags, pushes, or publishing';
        return %plan;
    }

    if $action eq 'tag' {
        # Test immediately before creating the tag, then revalidate.
        my %test = command(%plan<path>, 'zef', 'test', '.');
        die "zef test failed: {%test<stderr>.trim || %test<stdout>.trim}"
            unless %test<ok>;
        my %again = release-plan(%plan<path>, :$remote);
        die 'Repository or version changed while running tests'
            unless %again<head> eq %plan<head> and
                %again<version> eq %plan<version> and
                not %again<tag-exists>;
    }
    if $action eq 'tag' or $action eq 'push-tag' {
        # Refuse an existing remote tag (even if it points at this commit).
        my %lookup = command(%plan<path>, 'git', '-C', %plan<path>,
            'ls-remote', '--tags', '--refs', %plan<remote>,
            'refs/tags/' ~ %plan<tag>);
        die 'Cannot verify remote tag state' unless %lookup<ok>;
        die 'Tag already exists on the remote' if %lookup<stdout>.trim.chars;
        # Ensure remote branch has not moved since the last local fetch.
        my %head = command(%plan<path>, 'git', '-C', %plan<path>,
            'ls-remote', '--heads', %plan<remote>, %plan<branch>);
        die 'Cannot verify remote branch' unless %head<ok>;
        my @fields = %head<stdout>.words;
        die 'Remote branch is missing or does not match local HEAD'
            unless @fields.elems == 2 and @fields[0] eq %plan<head>;
    }
    if $action eq 'github' {
        my %lookup = command(%plan<path>, 'git', '-C', %plan<path>,
            'ls-remote', '--tags', '--refs', %plan<remote>,
            'refs/tags/' ~ %plan<tag>);
        die 'Cannot verify remote tag' unless %lookup<ok>;
        my @remote-tag = %lookup<stdout>.words;
        die 'Release tag is missing on the remote'
            unless @remote-tag.elems == 2;
        my $local-tag-object = checked(%plan<path>, 'rev-parse',
            'refs/tags/' ~ %plan<tag>);
        die 'Remote tag differs from the local tag'
            unless @remote-tag[0] eq $local-tag-object;
    }
    my %result = command(%plan<path>, $program, |@args);
    die "$program failed: {%result<stderr>.trim || %result<stdout>.trim}"
        unless %result<ok>;
    %plan<message> = %result<stdout>.trim || "$action completed";
    return %plan;
}
