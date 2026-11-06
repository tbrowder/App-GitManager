unit module App::GitManager::Git;

use App::GitManager::Result;

# Do not invoke a shell; arguments are passed directly to Git.
# --no-optional-locks prevents the optional index refresh done by git status.
sub run-git(Str:D $repo, *@args --> App::GitManager::Result) is export {
    my $proc = run 'git', '--no-optional-locks', '-C', $repo,
        |@args, :out, :err;

    my $stdout = $proc.out.slurp(:close);
    my $stderr = $proc.err.slurp(:close);

    return App::GitManager::Result.new(
        exit-code => $proc.exitcode,
        :$stdout,
        :$stderr,
    );
}
