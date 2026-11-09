use Test;
use App::GitManager::Sync;
use App::GitManager::Status;

# No real GitHub access. Tests use a temporary bare remote and clones.
my $parent = $*TMPDIR.add("gitmanager-sync-{$*PID}-" ~ now.Int);
$parent.mkdir;
my $bare = $parent.add('remote.git');
my $seed = $parent.add('seed');
my $client = $parent.add('client');

sub git(Str:D $where, *@args --> Int) {
    my $proc = run 'git', '-C', $where, |@args, :out, :err;
    $proc.out.slurp(:close);
    $proc.err.slurp(:close);
    return $proc.exitcode;
}

sub write-commit(Str:D $where, Str:D $file, Str:D $value --> Nil) {
    $where.IO.add($file).spurt($value);
    is git($where, 'add', $file), 0, "staged $file";
    is git($where, '-c', 'user.name=Test',
        '-c', 'user.email=test@example.invalid', 'commit', '-qm', $value),
        0, "committed $file";
}

is git($parent.Str, 'init', '--bare', '-q', $bare.Str), 0,
    'created bare remote';
is git($parent.Str, 'init', '-q', $seed.Str), 0,
    'created source repository';
is git($seed.Str, 'checkout', '-qb', 'master'), 0,
    'created master branch';
write-commit($seed.Str, 'initial.txt', 'first');
is git($seed.Str, 'remote', 'add', 'origin', $bare.Str), 0,
    'added remote';
is git($seed.Str, 'push', '-qu', 'origin', 'master'), 0,
    'published initial branch';
is git($bare.Str, 'symbolic-ref', 'HEAD', 'refs/heads/master'), 0,
    'configured bare remote HEAD';
is git($parent.Str, 'clone', '-q', $bare.Str, $client.Str), 0,
    'cloned working repository';

my %preview = sync-repo($client.Str, :dry-run);
ok %preview<dry-run>, 'dry run marked as preview';
ok not %preview<fetch-performed>, 'dry run did not fetch';

write-commit($seed.Str, 'second.txt', 'second');
is git($seed.Str, 'push', '-q', 'origin', 'master'), 0,
    'published second commit';
my %before = inspect-repo($client.Str);
is %before<behind>, 0, 'before fetch cached branch is not behind';
my %sync = sync-repo($client.Str);
ok %sync<fetch-performed>, 'sync fetched remote';
ok %sync<fast-forward-performed>, 'sync fast-forwarded';
ok not %sync<push-performed>, 'sync did not push by default';
is %sync<behind>, 0, 'sync left no cached commits behind';
ok $client.add('second.txt').f, 'fast-forward retrieved file';

$client.add('dirty.txt').spurt('not staged');
dies-ok { sync-repo($client.Str) }, 'dirty tree refused';
$client.add('dirty.txt').unlink;

write-commit($client.Str, 'local.txt', 'local');
my %ahead = sync-repo($client.Str);
is %ahead<ahead>, 1, 'local commit remains without --push';
ok not %ahead<push-performed>, 'did not push local commit';
my %published = sync-repo($client.Str, :push);
ok %published<push-performed>, 'explicit push published local commit';
is %published<ahead>, 0, 'published branch no longer ahead';

# The remote advances independently, then the client adds a local commit.
is git($seed.Str, 'pull', '--rebase', 'origin', 'master'), 0,
    'seed updated from client push';
write-commit($seed.Str, 'remote.txt', 'remote');
is git($seed.Str, 'push', '-q', 'origin', 'master'), 0,
    'seed published remote advancement';
write-commit($client.Str, 'diverged.txt', 'diverged');
dies-ok { sync-repo($client.Str) }, 'divergent branches refused';

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
