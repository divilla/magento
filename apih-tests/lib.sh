#!/usr/bin/env bash
# Shared lifecycle functions. All database mutations target the integration project.
set -euo pipefail

integration_repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
integration_runtime="$integration_repo/var/apih-integration"
integration_snapshot="$integration_repo/apih-tests/demo.sql"
cd -- "$integration_repo"

integration_compose() {
    docker compose --project-name magento2-integration \
        --env-file "$integration_runtime/environment" \
        -f "$integration_repo/apih-tests/compose.yaml" "$@"
}

integration_lock() {
    mkdir -p "$integration_runtime"
    exec 9>"$integration_runtime/run.lock"
    flock -n 9 || { printf 'Another integration setup/reset/run is active.\n' >&2; exit 1; }
}

integration_prepare() {
    if [[ ! -f "$integration_runtime/environment" ]]; then
        if docker volume inspect magento2-integration_integration-db-data >/dev/null 2>&1; then
            printf 'An integration database volume already exists, but var/apih-integration/environment is missing.\nRestore that file from the original checkout to keep the matching database passwords.\n' >&2
            exit 1
        fi
        (umask 077; cat > "$integration_runtime/environment" <<EOF
INTEGRATION_UID=$(id -u)
INTEGRATION_GID=$(id -g)
INTEGRATION_DB_PASSWORD=$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')
INTEGRATION_DB_ROOT_PASSWORD=$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')
EOF
        )
    fi
    for directory in var generated static media; do
        mkdir -p "$integration_runtime/$directory"
        chmod 0755 "$integration_runtime/$directory"
    done
    if [[ ! -f "$integration_runtime/etc/.prepared" ]]; then
        mkdir -p "$integration_runtime/etc"
        cp -a app/etc/. "$integration_runtime/etc/"
        cp -a pub/media/. "$integration_runtime/media/"
        cp pub/static/.htaccess "$integration_runtime/static/"
        BUILDX_CONFIG="$integration_runtime/buildx" integration_compose build integration-php
    fi
    # Keep the application login in sync after restoring the environment file.
    integration_compose run --rm --no-deps \
        -v "$integration_repo/app/etc/env.php:/tmp/demo-env.php:ro,z" \
        integration-php php apih-tests/prepare-env.php
    touch "$integration_runtime/etc/.prepared"
}

integration_check_database() {
    if ! integration_compose exec -T integration-db sh -eu -c '
        test "$MARIADB_DATABASE" = magento_integration
        test "$MARIADB_USER" = magento_integration
        MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -u root -N -e "SELECT 1" >/dev/null
        MYSQL_PWD="$MARIADB_PASSWORD" mariadb -h 127.0.0.1 -u "$MARIADB_USER" "$MARIADB_DATABASE" -N -e "SELECT 1" >/dev/null
    '; then
        printf 'Cannot authenticate to the integration database with var/apih-integration/environment.\nIf you moved this checkout, restore the original environment file; the database volume retains its original passwords.\n' >&2
        exit 1
    fi
}

integration_import() {
    local integration_source=$1
    [[ -s "$integration_source" ]] || { printf 'Missing SQL snapshot: %s\n' "$integration_source" >&2; exit 1; }
    # Our single-database dumps contain no schema switches or cross-database DDL.
    if rg -iq '^\s*(USE\s|(?:CREATE|DROP)\s+(?:DATABASE|SCHEMA)\s)' "$integration_source"; then
        printf 'Refusing a dump that switches or creates/drops databases.\n' >&2
        exit 1
    fi
    integration_compose exec -T integration-db sh -eu -c '
        test "$MARIADB_DATABASE" = magento_integration
        test "$MARIADB_USER" = magento_integration
        export MYSQL_PWD="$MARIADB_ROOT_PASSWORD"
        mariadb -u root -e "DROP DATABASE IF EXISTS magento_integration; CREATE DATABASE magento_integration CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
    '
    # Rebind trigger/view definers to the account on this separate server.
    sed -E 's/DEFINER=`[^`]+`@`[^`]+`/DEFINER=`magento_integration`@`%`/g' "$integration_source" |
    integration_compose exec -T integration-db sh -eu -c '
        test "$MARIADB_DATABASE" = magento_integration
        MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -u root magento_integration
    '
}

integration_clear_cache() {
    # This path is private to the integration application, never the demo's var/.
    rm -rf -- "$integration_runtime/var/cache" "$integration_runtime/var/page_cache" \
        "$integration_runtime/var/session" "$integration_runtime/var/view_preprocessed"
}

integration_baseline_counts() {
    integration_compose exec -T integration-db sh -eu -c '
        test "$MARIADB_DATABASE" = magento_integration
        MYSQL_PWD="$MARIADB_PASSWORD" mariadb -u "$MARIADB_USER" magento_integration -e "
            SELECT '\''products'\'' AS entity, COUNT(*) AS count FROM catalog_product_entity
            UNION ALL SELECT '\''customers'\'', COUNT(*) FROM customer_entity
            UNION ALL SELECT '\''orders'\'', COUNT(*) FROM sales_order;
        "
    '
}

integration_reset() {
    [[ -s "$integration_snapshot" ]] || { printf 'Run ./apih-tests/setup.sh to create demo.sql first.\n' >&2; exit 1; }
    (cd apih-tests && sha256sum --check demo.sql.sha256)
    integration_prepare
    integration_compose up -d --wait --wait-timeout 180 integration-db integration-search
    integration_check_database
    integration_compose stop integration-web integration-php
    printf 'Restoring demo.sql into the dedicated integration database...\n'
    integration_import "$integration_snapshot"
    integration_clear_cache
    # The saved snapshot may come from an older checkout than the current code.
    integration_compose run --rm --no-deps integration-php sh -eu -c '
        php bin/magento setup:upgrade
        php bin/magento indexer:reindex
    '
    integration_compose up -d integration-php integration-web
    integration_baseline_counts
    local integration_http_status
    for ((integration_attempt=0; integration_attempt<30; integration_attempt++)); do
        integration_http_status=$(curl -sS --max-time 3 -o /dev/null -w '%{http_code}' \
            http://localhost:8081/rest/default/V1/store/storeConfigs || true)
        if [[ "$integration_http_status" == 401 ]]; then
            return
        fi
        sleep 1
    done
    printf 'Integration API did not become ready on http://localhost:8081.\n' >&2
    exit 1
}
