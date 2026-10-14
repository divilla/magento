#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

docker compose version >/dev/null

random_password() {
    od -An -N16 -tx1 /dev/urandom | tr -d ' \n'
}

if [[ ! -f .env ]]; then
    (umask 077; cat > .env <<EOF
LOCAL_UID=$(id -u)
LOCAL_GID=$(id -g)
MAGENTO_DB_PASSWORD=$(random_password)
MAGENTO_DB_ROOT_PASSWORD=$(random_password)
EOF
    )
fi

set -a
source .env
set +a

if [[ -z "${MAGENTO_ADMIN_PASSWORD:-}" ]]; then
    MAGENTO_ADMIN_PASSWORD="Local$(random_password)!"
    export MAGENTO_ADMIN_PASSWORD
    printf '\nMAGENTO_ADMIN_PASSWORD=%s\n' "$MAGENTO_ADMIN_PASSWORD" >> .env
fi

docker compose up -d --build --wait --wait-timeout 300

# MariaDB only applies its initial passwords when the data volume is empty.
# Check the application login before Composer or setup:install can run.
docker compose exec -T -e MAGENTO_DB_PASSWORD php php -r '
    try {
        $db = new PDO("mysql:host=db;dbname=magento", "magento", getenv("MAGENTO_DB_PASSWORD"));
    } catch (PDOException $exception) {
        fwrite(STDERR, "Cannot connect to the existing Magento database with MAGENTO_DB_PASSWORD from .env.\n"
            . "If you moved this checkout, restore its original .env; the Docker database volume keeps its original passwords.\n");
        exit(1);
    }
    $env = is_file("app/etc/env.php") ? include "app/etc/env.php" : [];
    if (!isset($env["install"]["date"]) && $db->query("SHOW TABLES")->fetchColumn() !== false) {
        fwrite(STDERR, "The Magento database already contains tables, but this checkout has no installed configuration.\n"
            . "Restore app/etc/env.php and app/etc/config.php from the original checkout before starting.\n"
            . "Also restore any custom or sample-data modules and pub/media used by that store.\n");
        exit(1);
    }
'

docker compose exec -T php composer install --no-dev --prefer-dist --no-interaction

if ! docker compose exec -T php php -r '
    $env = is_file("app/etc/env.php") ? include "app/etc/env.php" : [];
    exit(isset($env["install"]["date"]) ? 0 : 1);
'; then
    docker compose exec -T \
        -e MAGENTO_DB_PASSWORD -e MAGENTO_ADMIN_PASSWORD php sh -eu -c '
        php bin/magento setup:install \
            --base-url=http://localhost:8080/ \
            --db-host=db --db-name=magento --db-user=magento \
            --db-password="$MAGENTO_DB_PASSWORD" \
            --backend-frontname=admin \
            --admin-firstname=Local --admin-lastname=Admin \
            --admin-email=admin@example.test --admin-user=admin \
            --admin-password="$MAGENTO_ADMIN_PASSWORD" \
            --language=en_US --currency=EUR --timezone=Europe/Zagreb \
            --use-rewrites=1 --use-secure=0 --use-secure-admin=0 \
            --session-save=files --search-engine=opensearch \
            --opensearch-host=opensearch --opensearch-port=9200 \
            --opensearch-enable-auth=0
        php bin/magento deploy:mode:set developer
        php bin/magento indexer:reindex
        php bin/magento cache:flush
    '
fi

docker compose exec -T php php bin/magento setup:db:status
printf '\nStorefront: http://localhost:8080/\n'
docker compose exec -T php php bin/magento info:adminuri
printf 'Admin username: admin\nAdmin password: see MAGENTO_ADMIN_PASSWORD in .env\n'
printf 'Stop services with: docker compose down\n'
