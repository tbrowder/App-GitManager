use Test;
use App::GitManager::CLI;
use App::GitManager::PR;

is run-cli(['pr']), 2, 'PR requires an action';
is run-cli(['pr', 'delete']), 2, 'unsupported PR action rejected';
is run-cli(['pr', 'view']), 2, 'PR view requires number';
is run-cli(['pr', 'merge']), 2, 'PR merge requires number';
is run-cli(['pr', 'merge', '1', '--all']), 2, 'bulk PR merge rejected';
is run-cli(['pr', 'create', '--push']), 2, 'implicit PR push rejected';
is run-cli(['pr', 'merge', '1', '--no-interactive']), 2,
    'noninteractive merge requires authorization';
is run-cli(['pr', 'create', '--merge-method=squash']), 2,
    'merge method invalid for create';
is run-cli(['pr', 'list', '--title=abc']), 2,
    'title option invalid for list';
done-testing;
