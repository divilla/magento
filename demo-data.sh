#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

./start.sh

sample_source=var/sample-data
if [[ ! -d "$sample_source" ]]; then
    git clone --depth 1 --branch 2.4-develop \
        https://github.com/magento/magento2-sample-data.git "$sample_source"
fi

# Relative links work both on the host and inside the PHP container.
for module in "$sample_source"/app/code/Magento/*SampleData; do
    module_name="${module##*/}"
    destination="app/code/Magento/$module_name"
    if [[ ! -e "$destination" && ! -L "$destination" ]]; then
        ln -s "../../../$module" "$destination"
    fi
done

# Keep existing media files when adding the demo images.
cp -an "$sample_source/pub/media/." pub/media/

mkdir -p var/backups
backup="var/backups/before-demo-$(date -u +%Y%m%dT%H%M%SZ).sql"
(umask 077; docker compose exec -T db sh -eu -c '
    MYSQL_PWD="$MARIADB_PASSWORD" mariadb-dump --single-transaction \
        -u "$MARIADB_USER" "$MARIADB_DATABASE"
' > "$backup")
printf 'Database backup: %s\n' "$backup"

docker compose exec -T php php bin/magento setup:upgrade
docker compose exec -T php php bin/magento indexer:reindex
docker compose exec -T php php bin/magento cache:flush
# Clear persisted file caches so the previous empty homepage is replaced.
docker compose exec -T php sh -eu -c 'rm -rf var/cache/* var/page_cache/*'
docker compose restart php

printf '\nDemo storefront: http://localhost:8080/\n'
