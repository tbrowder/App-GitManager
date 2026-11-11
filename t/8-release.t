use Test;
use App::GitManager::CLI;
use App::GitManager::Release;

is run-cli(['release']), 2, 'release requires an action';
is run-cli(['release', 'frobnicate']), 2, 'unknown action refused';
is run-cli(['release', 'tag', '--all']), 2, 'bulk release refused';
is run-cli(['release', 'tag', '--push']), 2, 'implicit push refused';
is run-cli(['release', 'tag', '--delete']), 2, 'delete option refused';
is run-cli(['release', 'tag', '--base=master']), 2,
    'unrelated base option refused';
is run-cli(['release', 'check', '--repo=/no-such-repo']), 1,
    'missing repo rejected';
is run-cli(['release', 'github', '--repo=/no-such-repo',
    '--dry-run']), 1, 'dry run does not mask invalid repository';
done-testing;
