use Test;
use App::GitManager::Status;

is github-slug('ssh://git@github.com/tbrowder/Ask.git'),
    'tbrowder/Ask', 'GitHub ssh URL accepted';
is github-slug('git@example.com:abc/def'), '',
    'non-GitHub SSH URL rejected';
done-testing;
