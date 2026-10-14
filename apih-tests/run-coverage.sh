#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
integration_lock
command -v apih >/dev/null
integration_minimum=${APIH_COVERAGE_MIN:-0}
integration_html=${APIH_COVERAGE_HTML:-0}
integration_cache=${APIH_COVERAGE_CACHE:-0}
if [[ ! $integration_html =~ ^[01]$ || ! $integration_cache =~ ^[01]$ ]]; then
    printf 'APIH_COVERAGE_HTML and APIH_COVERAGE_CACHE must be 0 or 1.\n' >&2
    exit 2
fi
integration_report_memory=2G
if [[ $integration_html == 1 ]]; then
    integration_report_memory=8G
fi
if [[ ! $integration_minimum =~ ^([0-9]+)(\.[0-9]+)?$ ]] || ! awk -v minimum="$integration_minimum" 'BEGIN { exit !(minimum <= 100) }'; then
    printf 'APIH_COVERAGE_MIN must be a percentage between 0 and 100.\n' >&2
    exit 2
fi

# Prepare/build the ordinary PHP image first; coverage extends that local image.
integration_prepare
integration_coverage=1
integration_restore_php() {
    rm -f -- "$integration_runtime/var/coverage/active.json"
    integration_coverage=0
    integration_compose up -d --no-deps integration-php integration-web
}
trap integration_restore_php EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
BUILDX_CONFIG="$integration_runtime/buildx" integration_compose build integration-php
integration_reset

integration_run_id=$(date -u +%Y%m%dT%H%M%SZ)-$$
integration_report="$integration_runtime/var/coverage/$integration_run_id"
mkdir -p "$integration_report/raw"
printf '{"directory":"/var/www/html/var/coverage/%s"}\n' \
    "$integration_run_id" > "$integration_runtime/var/coverage/active.json"
printf 'Measuring REST-test execution across production PHP...\n'
set +e
apih ./apih-tests
integration_test_exit=$?
set -e
# Wait for FPM shutdown hooks before merging; exclude readiness/setup requests.
integration_compose stop integration-php
rm -f -- "$integration_runtime/var/coverage/active.json"
set +e
integration_compose run --rm --no-deps -e XDEBUG_MODE=coverage \
    -e "APIH_COVERAGE_HTML=$integration_html" -e "APIH_COVERAGE_CACHE=$integration_cache" integration-php \
    php -d "memory_limit=$integration_report_memory" apih-tests/code-coverage/report.php "$integration_run_id" \
    "$integration_test_exit" "$integration_minimum"
integration_report_exit=$?
set -e
printf 'Coverage summary: %s/summary.md\n' "$integration_report"
if [[ $integration_test_exit != 0 ]]; then
    exit "$integration_test_exit"
fi
if [[ $integration_report_exit != 0 ]]; then
    printf 'Coverage reporting failed or did not meet the minimum.\n' >&2
    exit 2
fi
