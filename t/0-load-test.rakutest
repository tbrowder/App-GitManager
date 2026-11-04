use Test;

my @modules = <
    App::GitManager
>;

plan @modules.elems;

for @modules -> $m {
    use-ok $m, "Module '$m' used okay";
}
