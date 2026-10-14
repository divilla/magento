<?php
declare(strict_types=1);

// Only the isolated FPM server, during the runner's measurement window.
$active = '/var/www/html/var/coverage/active.json';
if (PHP_SAPI !== 'fpm-fcgi' || !is_file($active)) {
    return;
}
$run = json_decode(file_get_contents($active), true, 512, JSON_THROW_ON_ERROR);
require __DIR__ . '/scope.php';
$directories = apihCoverageDirectories();
xdebug_set_filter(XDEBUG_FILTER_CODE_COVERAGE, XDEBUG_PATH_INCLUDE, $directories);
xdebug_start_code_coverage(XDEBUG_CC_UNUSED | XDEBUG_CC_DEAD_CODE);

register_shutdown_function(static function () use ($run, $directories): void {
    $data = array_filter(
        xdebug_get_code_coverage(),
        static fn (string $file): bool => apihCoverageIncludes($file, $directories),
        ARRAY_FILTER_USE_KEY
    );
    xdebug_stop_code_coverage();
    // No request bodies, URLs, headers, or credential values are recorded.
    $file = $run['directory'] . '/raw/' . bin2hex(random_bytes(12)) . '.json';
    $temporary = $file . '.tmp';
    if (file_put_contents($temporary, json_encode($data, JSON_THROW_ON_ERROR)) === false
        || !rename($temporary, $file)) {
        error_log('APIHydra coverage could not save request data.');
    }
});
