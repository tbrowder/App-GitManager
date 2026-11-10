use Test;
use App::GitManager::PR;
use App::GitManager::CLI;

my $parent = $*TMPDIR.add("gitmanager-pr-{$*PID}-" ~ now.Int);
$parent.mkdir;
my $repo = $parent.add('example');
$repo.mkdir;

sub git(*@args --> Int) {
    my $process = run 'git', '-C', $repo.Str, |@args, :out, :err;
    $process.out.slurp(:close);
    $process.err.slurp(:close);
    return $process.exitcode;
}

is git('init', '-q'), 0, 'repository initialized';
is git('config', 'user.email', 'test@example.invalid'), 0,
    'identity configured';
is git('config', 'user.name', 'GitManager Test'), 0,
    'name configured';
$repo.add('sample.txt').spurt('sample');
is git('add', 'sample.txt'), 0, 'sample staged';
is git('commit', '-qm', 'Initial'), 0, 'sample committed';
is git('remote', 'add', 'origin',
    'git@github.com:tbrowder/example.git'), 0, 'GitHub remote configured';

my %list = pr-action($repo.Str, 'list', :dry-run);
ok %list<dry-run>, 'list preview is read-only';
is %list<repository>, 'tbrowder/example', 'GitHub slug resolved';
my %create = pr-action($repo.Str, 'create', :title('Feature'),
    :base('master'), :dry-run);
ok %create<dry-run>, 'create preview without gh';
ok %create<arguments>.join(' ').contains('--head'),
    'create uses current branch';
my %merge = pr-action($repo.Str, 'merge', :number('12'),
    :merge-method('squash'), :dry-run);
ok %merge<dry-run>, 'merge preview without gh';
ok %merge<mutating>, 'merge is classified as a mutating operation';
ok %merge<arguments>.join(' ').contains('--squash'),
    'explicit merge method used';
dies-ok { pr-action($repo.Str, 'merge', :number('abc'), :dry-run) },
    'invalid PR number rejected';
dies-ok { pr-action($repo.Str, 'create', :title('Feature'), :dry-run) },
    'missing base rejected';
dies-ok { pr-action($repo.Str, 'create', :base('master'), :dry-run) },
    'missing title rejected';
is run-cli(['pr', 'list', '--repo=' ~ $repo.Str, '--dry-run']), 0,
    'CLI list preview';
is run-cli(['pr', 'merge', '12', '--repo=' ~ $repo.Str,
    '--dry-run']), 0, 'CLI merge preview';

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
