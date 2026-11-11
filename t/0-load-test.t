use Test;

my @modules = <
    App::GitManager
    App::GitManager::Result
    App::GitManager::Git
    App::GitManager::Status
    App::GitManager::CLI
    App::GitManager::Sync
    App::GitManager::Alias
    App::GitManager::PR
    App::GitManager::PruneBranches
    App::GitManager::Release
>;

plan @modules.elems;

for @modules -> $m {
    use-ok $m, "Module '$m' used okay";
}
