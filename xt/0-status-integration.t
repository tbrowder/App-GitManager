use Test;
use App::GitManager::Status;

# Integration tests create temporary repositories, never modify user repos.
my $parent = $*TMPDIR.add("gitmanager-{$*PID}-" ~ now.Int);
$parent.mkdir;
my $repo = $parent.add('sample');
$repo.mkdir;

sub git(*@args --> Int) {
    my $proc = run 'git', '-C', $repo.Str, |@args, :out, :err;
    $proc.out.slurp(:close);
    $proc.err.slurp(:close);
    return $proc.exitcode;
}

is git('init', '-q'), 0, 'initialized temporary repo';
my %initial = inspect-repo($repo.Str);
ok %initial<unborn>, 'unborn branch detected';
ok %initial<clean>, 'empty repo clean';

$repo.add('new.txt').spurt('untracked');
my %untracked = inspect-repo($repo.Str);
is %untracked<untracked>, 1, 'untracked file counted';
ok not %untracked<clean>, 'untracked repository is not clean';

is git('add', 'new.txt'), 0, 'staged file';
my %staged = inspect-repo($repo.Str);
is %staged<staged>, 1, 'staged file counted';

is git('-c', 'user.name=Test', '-c', 'user.email=test@example.invalid',
    'commit', '-qm', 'initial'), 0, 'committed sample';
my %committed = inspect-repo($repo.Str);
ok %committed<clean>, 'committed repository clean';
ok not %committed<unborn>, 'repository has commits';

my @paths = repository-paths($parent.Str);
is @paths.elems, 1, '--all discovers direct child repository';

# Recursively clean up only the temporary tree created by this test.
sub remove-tree(IO::Path:D $path --> Nil) {
    if $path.d and not $path.l {
        for $path.dir -> $entry {
            remove-tree($entry);
        }
        $path.rmdir;
    }
    else {
        $path.unlink;
    }
}
remove-tree($parent);
done-testing;
