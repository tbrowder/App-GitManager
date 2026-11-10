use Test;

my @modules = <
    App::GitManager
    App::GitManager::Alias
    App::GitManager::CLI
    App::GitManager::Git
    App::GitManager::PR
    App::GitManager::Result
    App::GitManager::Status
    App::GitManager::Sync
>;

plan @modules.elems;

for @modules -> $m {
    use-ok $m, "Module '$m' used okay";
}
