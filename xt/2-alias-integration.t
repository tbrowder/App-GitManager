use Test;
use App::GitManager::Alias;
use App::GitManager::CLI;

my $parent = $*TMPDIR.add("gitmanager-alias-{$*PID}-" ~ now.Int);
$parent.mkdir;
my $repo = $parent.add('example');
$repo.mkdir;
my $config = $parent.add('config').add('repos.json');
my $original = %*ENV<GITMANAGER_CONFIG>;
%*ENV<GITMANAGER_CONFIG> = $config.Str;
LEAVE {
    if $original.defined {
        %*ENV<GITMANAGER_CONFIG> = $original;
    }
    else {
        %*ENV<GITMANAGER_CONFIG>:delete;
    }
}

sub git(*@args --> Int) {
    my $process = run 'git', '-C', $repo.Str, |@args, :out, :err;
    $process.out.slurp(:close);
    $process.err.slurp(:close);
    return $process.exitcode;
}

is git('init', '-q'), 0, 'temporary repository initialized';
ok not $config.e, 'config absent initially';
my %preview = add-alias('example', $repo.Str, :dry-run);
ok %preview<dry-run>, 'add dry run identified';
ok not $config.e, 'add dry run did not write';
my %added = add-alias('example', $repo.Str);
ok $config.f, 'configuration created';
is resolve-repo('example'), $repo.absolute.Str, 'alias resolves to repository';
is run-cli(['status', '-r', 'example']), 0, 'status accepts alias';
is run-cli(['status', '--repo=example']), 0, 'long repo option accepts alias';
is run-cli(['alias', 'show', 'example']), 0, 'show alias';
is run-cli(['alias', 'list']), 0, 'list aliases';
is run-cli(['alias', 'add', 'another', $repo.Str, '--yes']), 0,
    'CLI creates alias without prompting when authorized';
is run-cli(['alias', 'remove', 'another', '--yes']), 0,
    'CLI removes alias when authorized';
dies-ok { add-alias('example', $repo.Str) }, 'duplicate alias refused';
my %removed-preview = remove-alias('example', :dry-run);
ok %removed-preview<dry-run>, 'remove dry run identified';
is resolve-repo('example'), $repo.absolute.Str, 'dry run preserved alias';
my %removed = remove-alias('example');
dies-ok { resolve-repo('example') }, 'removed alias no longer resolves';

# Remove only the temporary fixture created by this integration test.
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
