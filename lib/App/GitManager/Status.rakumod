unit module App::GitManager::Status;

use App::GitManager::Git;

# Recognize GitHub HTTPS and SSH remotes, but do not assume that every
# origin is hosted at GitHub. Never make a network request here.
sub github-slug(Str:D $url --> Str) is export {
    my $value = $url.trim;
    if $value ~~ /^ 'git@github.com:' (.+) $/ {
        $value = ~$0;
    }
    elsif $value ~~ /^ 'ssh://git@github.com/' (.+) $/ {
        $value = ~$0;
    }
    elsif $value ~~ /^ 'https://github.com/' (.+) $/ {
        $value = ~$0;
    }
    else {
        return '';
    }

    $value = $value.substr(0, $value.chars - 4)
        if $value.ends-with('.git');
    my @parts = $value.split('/');
    return $value if @parts.elems == 2 and
        @parts[0].chars and @parts[1].chars;
    return '';
}

sub checked(Str:D $repo, *@args --> Str) {
    my $result = run-git($repo, |@args);
    die "Git failed: {@args.join(' ')}: {$result.stderr.trim}"
        unless $result.success;
    return $result.stdout;
}

sub inspect-repo(Str:D $path, Str :$remote = 'origin' --> Hash) is export {
    my $root = checked($path, 'rev-parse', '--show-toplevel').trim;
    die "Not a working-tree Git repository: $path" unless $root.chars;

    my %report = (
        path             => $root,
        name             => $root.IO.basename,
        remote           => $remote,
        branch           => '',
        detached         => False,
        unborn           => False,
        upstream         => '',
        ahead            => Nil,
        behind           => Nil,
        remote-url       => '',
        github           => '',
        staged           => 0,
        unstaged         => 0,
        untracked        => 0,
        conflicted       => 0,
        clean            => True,
        local-branches   => [],
        remote-branches  => [],
        upstream-source  => 'cached remote-tracking references',
    );

    my $branch = run-git($root, 'symbolic-ref', '--quiet', '--short', 'HEAD');
    if $branch.success {
        %report<branch> = $branch.stdout.trim;
    }
    else {
        %report<detached> = True;
        %report<branch> = '(detached HEAD)';
    }

    my $head = run-git($root, 'rev-parse', '--verify', 'HEAD');
    %report<unborn> = (not $head.success);

    # NUL-delimited porcelain handles filenames containing newlines.
    # Rename and copy entries have one extra original-filename record.
    my $status = checked($root, 'status', '--porcelain=v1', '-z',
        '--untracked-files=normal');
    my @entries = $status.split("\0");
    my $index = 0;
    while $index < @entries.elems {
        my $line = @entries[$index++];
        next unless $line.chars >= 3;
        my $x = $line.substr(0, 1);
        my $y = $line.substr(1, 1);
        if $x eq '?' and $y eq '?' {
            %report<untracked>++;
        }
        elsif $x eq 'U' or $y eq 'U' or
              ($x eq 'A' and $y eq 'A') or
              ($x eq 'D' and $y eq 'D') {
            %report<conflicted>++;
        }
        else {
            %report<staged>++ if $x ne ' ';
            %report<unstaged>++ if $y ne ' ';
        }
        if $x eq 'R' or $y eq 'R' or $x eq 'C' or $y eq 'C' {
            $index++;  # Skip original pathname from -z porcelain entry.
        }
    }
    %report<clean> = (
        %report<staged> == 0 and
        %report<unstaged> == 0 and
        %report<untracked> == 0 and
        %report<conflicted> == 0
    );

    my $upstream = run-git($root, 'rev-parse', '--abbrev-ref',
        '--symbolic-full-name', '@{upstream}');
    if $upstream.success and not %report<unborn> {
        %report<upstream> = $upstream.stdout.trim;
        my $counts = run-git($root, 'rev-list', '--left-right', '--count',
            'HEAD...@{upstream}');
        if $counts.success {
            my @parts = $counts.stdout.words;
            if @parts.elems == 2 {
                %report<ahead> = @parts[0].Int;
                %report<behind> = @parts[1].Int;
            }
        }
    }

    my $url = run-git($root, 'remote', 'get-url', $remote);
    if $url.success {
        %report<remote-url> = $url.stdout.trim;
        %report<github> = github-slug(%report<remote-url>);
    }

    my $local = checked($root, 'branch', '--list', '--format=%(refname:short)');
    my $remotes = checked($root, 'branch', '-r', '--format=%(refname:short)');
    my @local-branches;
    my @remote-branches;
    for $local.lines -> $name {
        @local-branches.push($name) if $name.chars;
    }
    for $remotes.lines -> $name {
        @remote-branches.push($name) if $name.chars;
    }
    %report<local-branches> = @local-branches.Array;
    %report<remote-branches> = @remote-branches.Array;

    return %report;
}

# --all intentionally scans only immediate subdirectories. A Git worktree
# uses a .git file instead of a directory; .e checks for either form.
sub repository-paths(Str:D $parent --> Array) is export {
    my $directory = $parent.IO.absolute.IO;
    die "Directory not found: $parent" unless $directory.d;

    my @paths;
    for $directory.dir.sort(*.basename) -> $entry {
        next unless $entry.d;
        next unless $entry.add('.git').e;
        @paths.push($entry.absolute.Str);
    }
    return @paths.Array;
}
