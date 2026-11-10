use Test;
use App::GitManager::Alias;

ok valid-name('tu'), 'short alias accepted';
ok valid-name('text-utils'), 'hyphenated alias accepted';
nok valid-name('bad/name'), 'slash disallowed';
nok valid-name('.'), 'current directory is not an alias';
nok valid-name('-no'), 'leading dash disallowed';

done-testing;
