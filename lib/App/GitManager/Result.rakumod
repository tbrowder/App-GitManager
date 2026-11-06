unit class App::GitManager::Result;

has Int $.exit-code = 0;
has Str $.stdout = '';
has Str $.stderr = '';

method success(--> Bool) {
    return $!exit-code == 0;
}
