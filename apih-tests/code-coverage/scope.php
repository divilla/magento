<?php
declare(strict_types=1);

// A conservative source scope: dynamic REST dispatch cannot establish an exact
// static reachability boundary. Untouched production files stay in the denominator.
function apihCoverageDirectories(): array
{
    $root = dirname(__DIR__, 2);
    return [$root . '/app/code/', $root . '/lib/internal/', $root . '/vendor/'];
}

function apihCoverageIncludes(string $file, array $directories): bool
{
    foreach ($directories as $directory) {
        if (str_starts_with($file, $directory)) {
            $relative = substr($file, strlen($directory));
            return str_ends_with($file, '.php')
                && !preg_match('~(?:^|/)(?:tests?|_files|fixtures?|examples?|docs?|\.git)/~i', $relative);
        }
    }
    return false;
}
