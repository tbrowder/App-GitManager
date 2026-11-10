unit module App::GitManager::Alias;

use JSON::Fast;
use App::GitManager::Git;

# GITMANAGER_CONFIG is useful for tests and intentionally allows independent
# configuration files for different workflows.
sub config-path(--> IO::Path) is export {
    if %*ENV<GITMANAGER_CONFIG>:exists and %*ENV<GITMANAGER_CONFIG>.chars {
        return %*ENV<GITMANAGER_CONFIG>.IO.absolute.IO;
    }
    my $base = %*ENV<XDG_CONFIG_HOME> // '';
    my $directory = $base.chars
        ?? $base.IO
        !! $*HOME.add('.config');
    return $directory.add('gitmanager').add('repos.json').absolute.IO;
}

sub valid-name(Str:D $name --> Bool) is export {
    return so $name ~~ /^ <[A..Za..z0..9]> <[A..Za..z0..9_\-]>* $/;
}

sub read-aliases(--> Hash) is export {
    my $file = config-path();
    return {} unless $file.e;
    die "Alias configuration is not a file: $file" unless $file.f;
    my $decoded = from-json($file.slurp);
    die 'Alias configuration must contain a JSON object'
        unless $decoded ~~ Associative;
    my %aliases;
    for $decoded.kv -> $name, $path {
        die "Invalid saved alias name: $name" unless valid-name($name);
        die "Invalid saved path for alias $name" unless $path ~~ Str;
        %aliases{$name} = $path;
    }
    return %aliases;
}

sub save-aliases(%aliases --> Nil) is export {
    my $file = config-path();
    $file.parent.mkdir(:parents);
    my $temporary = $file.parent.add(".repos-{$*PID}-{now.Int}.tmp");
    LEAVE $temporary.unlink if $temporary.e;
    $temporary.spurt(to-json(%aliases) ~ "\n");
    die "Cannot replace alias configuration: $file"
        unless $temporary.rename($file);
}

sub repo-root(Str:D $path --> Str) is export {
    die "Repository directory not found: $path" unless $path.IO.d;
    my $result = run-git($path, 'rev-parse', '--show-toplevel');
    die "Not a working Git repository: $path" unless $result.success;
    return $result.stdout.trim.IO.absolute;
}

sub add-alias(Str:D $name, Str:D $path, Bool :$dry-run = False
    --> Hash) is export {
    die "Invalid alias name: $name" unless valid-name($name);
    my %aliases = read-aliases();
    die "Alias already exists: $name" if %aliases{$name}:exists;
    my $root = repo-root($path);
    %aliases{$name} = $root;
    save-aliases(%aliases) unless $dry-run;
    return { action => 'add', name => $name, path => $root,
        dry-run => $dry-run };
}

sub remove-alias(Str:D $name, Bool :$dry-run = False
    --> Hash) is export {
    my %aliases = read-aliases();
    die "Unknown alias: $name" unless %aliases{$name}:exists;
    my $root = %aliases{$name};
    %aliases{$name}:delete;
    save-aliases(%aliases) unless $dry-run;
    return { action => 'remove', name => $name, path => $root,
        dry-run => $dry-run };
}

sub resolve-repo(Str:D $value --> Str) is export {
    return '.' if $value eq '.';
    # Explicit existing paths always win over aliases.
    return $value if $value.IO.d;
    my %aliases = read-aliases();
    return %aliases{$value} if %aliases{$value}:exists;
    die "Unknown repository alias or directory: $value";
}
