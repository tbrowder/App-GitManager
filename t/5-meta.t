use Test;
use JSON::Fast;

my %meta = from-json('META6.json'.IO.slurp);
my %provides = %meta<provides>;
my %actual;
for 'lib'.IO.dir.sort -> $top {
    next unless $top.d;
    # Below, recurse explicitly to include any future nested namespaces.
    my @pending = $top;
    while @pending {
        my $entry = @pending.pop;
        for $entry.dir -> $child {
            if $child.d {
                @pending.push($child);
            }
            elsif $child.extension eq 'rakumod' {
                my $name = $child.Str.subst(/^ 'lib/' /, '')
                    .subst(/ '.rakumod' $ /, '')
                    .subst('/', '::', :g);
                %actual{$name} = $child.Str;
            }
        }
    }
}
is-deeply %provides, %actual,
    'META6.json provides matches every module in lib/';
done-testing;
