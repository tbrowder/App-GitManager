use Test;
use App::GitManager::Git;
use App::GitManager::Status;

my $result = run-git('.', '--version');
ok $result.success, 'git executable available';
like $result.stdout, /git/, 'git version captured';
is github-slug('git@github.com:tbrowder/Text-Utils.git'),
    'tbrowder/Text-Utils', 'SSH GitHub URL';
is github-slug('https://github.com/tbrowder/Text-Utils'),
    'tbrowder/Text-Utils', 'HTTPS GitHub URL';
is github-slug('https://example.org/a/b'), '',
    'non-GitHub host not labeled GitHub';
done-testing;
