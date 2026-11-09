use Test;
use App::GitManager::CLI;

is run-cli(['--help']), 0, 'help accepted';
is run-cli(['frobnicate']), 2, 'unsupported command rejected';
is run-cli(['status', '--bogus']), 2, 'unknown option rejected';
is run-cli(['status', '--repo']), 2, 'missing path rejected';
is run-cli(['sync', '--all']), 2, 'bulk synchronization rejected';
is run-cli(['status', '--push']), 2, 'status rejects push option';
done-testing;
