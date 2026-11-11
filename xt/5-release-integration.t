use Test;
use JSON::Fast;
use App::GitManager::CLI;
use App::GitManager::Git;
use App::GitManager::Release;

my $parent = $*TMPDIR.add("gitmanager-release-{$*PID}-" ~ now.Int);
$parent.mkdir;
LEAVE {
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
    remove-tree($parent) if $parent.e;
}
my $repo = $parent.add('repository');
my $bare = $parent.add('remote.git');
$repo.mkdir;
sub git(Str:D $path, *@args --> Int) {
    my $proc = run 'git', '-C', $path, |@args, :out, :err;
    $proc.out.slurp(:close);
    $proc.err.slurp(:close);
    return $proc.exitcode;
}
is git($repo.Str, 'init', '-q'), 0, 'repository initialized';
is git($repo.Str, 'config', 'user.name', 'GitManager Test'), 0,
    'author name configured';
is git($repo.Str, 'config', 'user.email', 'test@example.invalid'), 0,
    'author email configured';
is git($parent.Str, 'init', '--bare', '-q', $bare.Str), 0,
    'bare remote initialized';
$repo.add('META6.json').spurt(to-json({
    name => 'Example', version => '0.1.0',
}));
is git($repo.Str, 'add', 'META6.json'), 0, 'version metadata staged';
is git($repo.Str, 'commit', '-qm', 'Initial'), 0, 'version committed';
is git($repo.Str, 'branch', '-M', 'main'), 0, 'main branch selected';
is git($repo.Str, 'remote', 'add', 'origin', $bare.Str), 0,
    'local bare remote configured';
is git($repo.Str, 'push', '-qu', 'origin', 'main'), 0,
    'upstream established';

my %plan = release-plan($repo.Str);
is %plan<version>, '0.1.0', 'version comes from META6';
is %plan<tag>, '0.1.0', 'tag uses exact META6 version';
ok not(%plan<tag-exists>), 'tag does not exist';
is run-cli(['release', 'check', '--repo=' ~ $repo.Str]), 0,
    'read-only preflight succeeds';
is run-cli(['release', 'tag', '--repo=' ~ $repo.Str,
    '--dry-run']), 0, 'tag dry run succeeds without zef';
is git($repo.Str, 'show-ref', '--verify', '--quiet',
    'refs/tags/0.1.0'), 1, 'preview does not create tag';
is run-cli(['release', 'tag', '--repo=' ~ $repo.Str,
    '--no-interactive']), 2, 'tag requires authorization';
is run-cli(['release', 'push-tag', '--repo=' ~ $repo.Str,
    '--dry-run']), 1, 'missing local tag cannot be pushed';
$repo.add('untracked').spurt('dirty');
dies-ok { release-plan($repo.Str) }, 'untracked files block release';
$repo.add('untracked').unlink;
is git($repo.Str, 'tag', '-a', '0.1.0', '-m', 'Manual tag'), 0,
    'test tag created';
is run-cli(['release', 'tag', '--repo=' ~ $repo.Str,
    '--dry-run']), 1, 'duplicate tag refused';
is run-cli(['release', 'push-tag', '--repo=' ~ $repo.Str,
    '--dry-run']), 0, 'existing local tag can be previewed for push';
is run-cli(['release', 'github', '--repo=' ~ $repo.Str,
    '--dry-run']), 1, 'GitHub publishing refuses non-GitHub remote';
done-testing;
