#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
integration_lock

if [[ -e "$integration_snapshot" ]]; then
    printf 'demo.sql already exists. Use ./apih-tests/run.sh to restore and test it.\n'
    exit 0
fi
integration_source=${1:-var/backups/before-demo-20261013T041601Z.sql}
[[ -s "$integration_source" && -f app/etc/env.php && -d var/sample-data ]] || {
    printf 'A pre-demo SQL backup, installed demo configuration, and var/sample-data are required.\n' >&2
    exit 1
}
integration_prepare
integration_compose up -d --wait --wait-timeout 180 integration-db integration-search
integration_check_database
integration_compose stop integration-web integration-php
integration_import "$integration_source"
integration_clear_cache
printf 'Rebuilding the original demo data in the isolated database...\n'
integration_compose run --rm --no-deps integration-php sh -eu -c '
    php bin/magento setup:upgrade
    php bin/magento indexer:set-mode realtime cataloginventory_stock catalog_product_price
    php bin/magento indexer:reindex
    php bin/magento cache:flush
'
integration_baseline_counts
(umask 077; integration_compose exec -T integration-db sh -eu -c '
    test "$MARIADB_DATABASE" = magento_integration
    MYSQL_PWD="$MARIADB_PASSWORD" mariadb-dump --single-transaction \
        -u "$MARIADB_USER" magento_integration
' > "$integration_snapshot.tmp")
mv "$integration_snapshot.tmp" "$integration_snapshot"
(cd apih-tests && sha256sum demo.sql > demo.sql.sha256)
printf 'Saved clean demo baseline to apih-tests/demo.sql.\n'
