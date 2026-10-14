<?php
declare(strict_types=1);

require '/opt/apih-coverage/vendor/autoload.php';
require __DIR__ . '/scope.php';

use SebastianBergmann\CodeCoverage\CodeCoverage;
use SebastianBergmann\CodeCoverage\Data\RawCodeCoverageData;
use SebastianBergmann\CodeCoverage\Driver\Selector;
use SebastianBergmann\CodeCoverage\Filter;
use SebastianBergmann\CodeCoverage\Node\File;
use SebastianBergmann\CodeCoverage\Report\Clover;
use SebastianBergmann\CodeCoverage\Report\Html\Facade;

[$script, $runId, $testExit, $minimum] = $argv;
$root = dirname(__DIR__, 2);
$base = $root . '/var/coverage';
$directory = $base . '/' . $runId;
$generateHtml = getenv('APIH_COVERAGE_HTML') === '1';
$cacheAnalysis = getenv('APIH_COVERAGE_CACHE') === '1';
$directories = apihCoverageDirectories();
$filter = new Filter;
foreach ($directories as $sourceDirectory) {
    $iterator = new RecursiveIteratorIterator(new RecursiveDirectoryIterator(
        $sourceDirectory, FilesystemIterator::SKIP_DOTS
    ));
    foreach ($iterator as $file) {
        if ($file->isFile() && apihCoverageIncludes($file->getPathname(), $directories)) {
            $filter->includeFile($file->getPathname());
        }
    }
}
$coverage = new CodeCoverage((new Selector)->forLineCoverage($filter), $filter);
$coverage->includeUncoveredFiles();
$coverage->disableAnnotationsForIgnoringCode();
if ($cacheAnalysis) {
    $coverage->cacheStaticAnalysis($base . '/analysis-cache');
}
$requests = glob($directory . '/raw/*.json');
if (!$requests) {
    fwrite(STDERR, "No request coverage was collected.\n");
    exit(2);
}
foreach ($requests as $request) {
    $raw = json_decode(file_get_contents($request), true, 512, JSON_THROW_ON_ERROR);
    $coverage->append(RawCodeCoverageData::fromXdebugWithoutPathCoverage($raw), basename($request));
}
echo 'Analysing ', count($filter->files()), " production files, including untouched files...\n";
$report = $coverage->getReport();
$groups = [];
$files = [];
$observedTotal = $observedCovered = 0;
foreach ($report as $node) {
    if (!$node instanceof File) {
        continue;
    }
    $path = substr($node->pathAsString(), strlen($root) + 1);
    $segments = explode('/', $path);
    $group = match ($segments[0]) {
        'app' => implode('/', array_slice($segments, 0, 4)),
        'lib' => implode('/', array_slice($segments, 0, 4)),
        default => implode('/', array_slice($segments, 0, 3)),
    };
    $total = $node->numberOfExecutableLines();
    $covered = $node->numberOfExecutedLines();
    $groups[$group] ??= ['executable' => 0, 'covered' => 0, 'files' => 0, 'executed_files' => 0];
    $groups[$group]['executable'] += $total;
    $groups[$group]['covered'] += $covered;
    $groups[$group]['files']++;
    $groups[$group]['executed_files'] += (int) ($covered > 0);
    if ($covered > 0) {
        $observedTotal += $total;
        $observedCovered += $covered;
    }
    $files[$path] = ['executable' => $total, 'covered' => $covered];
}
ksort($groups);
ksort($files);
$total = $report->numberOfExecutableLines();
$covered = $report->numberOfExecutedLines();
$percentage = $total ? 100 * $covered / $total : 0;
$summary = [
    'run' => $runId,
    'measured_at' => gmdate(DATE_ATOM),
    'scope' => 'production-php-v1',
    'scope_note' => 'Conservative production PHP superset, not an exact REST reachability graph. '
        . 'Includes app/code, lib/internal, vendor; excludes test, fixture, example and doc directories. '
        . 'Includes untouched files and code for other entry points. Branch coverage is not measured.',
    'apih_exit' => (int) $testExit,
    'requests' => count($requests),
    'files' => count($files),
    'executed_files' => array_sum(array_column($groups, 'executed_files')),
    'executable_lines' => $total,
    'covered_lines' => $covered,
    'line_percent' => $percentage,
    'executed_files_line_percent' => $observedTotal ? 100 * $observedCovered / $observedTotal : 0,
    'minimum_percent' => (float) $minimum,
    'groups' => $groups,
    'file_coverage' => $files,
];
$previousPath = $base . '/latest/summary.json';
if (is_file($previousPath)) {
    $previous = json_decode(file_get_contents($previousPath), true, 512, JSON_THROW_ON_ERROR);
    if ($previous['scope'] === $summary['scope']) {
        $summary['previous_run'] = $previous['run'];
        $summary['change_percentage_points'] = $percentage - $previous['line_percent'];
    }
}
file_put_contents($directory . '/summary.json', json_encode($summary, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR) . "\n");
$markdown = "# REST-test source coverage\n\n" . $summary['scope_note'] . "\n\n"
    . sprintf("Run `%s`: **%.2f%%** (%d/%d executable lines), **%d/%d files executed**; %d HTTP requests; APIHydra exit **%d**.\n\n",
        $runId, $percentage, $covered, $total, $summary['executed_files'], count($files), count($requests), (int) $testExit)
    . sprintf("Coverage within files actually executed: **%.2f%%**. This narrower metric excludes untouched files and does not measure all potentially reachable REST code.\n\n", $summary['executed_files_line_percent']);
if (isset($summary['change_percentage_points'])) {
    $markdown .= sprintf("Change from `%s`: **%+.2f percentage points**.\n\n", $summary['previous_run'], $summary['change_percentage_points']);
}
$markdown .= ($generateHtml ? "[Browse covered and uncovered source lines](html/index.html). " : '')
    . "[Clover XML](clover.xml). [Machine-readable details](summary.json).\n\n"
    . "| Module / package | Covered / executable lines | Coverage | Executed / total files |\n| --- | ---: | ---: | ---: |\n";
foreach ($groups as $name => $counts) {
    $markdown .= sprintf("| %s | %d / %d | %.2f%% | %d / %d |\n", $name, $counts['covered'], $counts['executable'],
        $counts['executable'] ? 100 * $counts['covered'] / $counts['executable'] : 0, $counts['executed_files'], $counts['files']);
}
file_put_contents($directory . '/summary.md', $markdown);
(new Clover)->process($coverage, $directory . '/clover.xml');
if ($generateHtml) {
    (new Facade('APIHydra REST tests'))->process($coverage, $directory . '/html');
}
$history = $summary;
unset($history['groups'], $history['file_coverage']);
file_put_contents($base . '/history.jsonl', json_encode($history, JSON_THROW_ON_ERROR) . "\n", FILE_APPEND | LOCK_EX);
$temporaryLink = $base . '/latest-' . $runId;
symlink($runId, $temporaryLink);
rename($temporaryLink, $base . '/latest');
printf("REST tests covered %.2f%% of production PHP (%d/%d lines); %d/%d files executed.\n", $percentage, $covered, $total, $summary['executed_files'], count($files));
if ($percentage < (float) $minimum) {
    fwrite(STDERR, sprintf("Coverage is below the %.2f%% minimum.\n", (float) $minimum));
    exit(2);
}
