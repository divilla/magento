# Running Magento locally

Start Magento from the repository root:

```bash
./start.sh
```

The script starts the Docker Compose containers and installs Magento on the first run. Subsequent runs preserve the existing store and database.

- Storefront: http://localhost:8080
- Admin: http://localhost:8080/admin
- Admin username: `admin`
- Admin password: the `MAGENTO_ADMIN_PASSWORD` value in `.env`

Stop the containers:

```bash
docker compose down
```

The database remains saved in its Docker volume after stopping the containers.

## Moving the checkout

This stack uses the fixed Compose project name `magento2-local`, so moving the repository to a different directory reuses the same database and search volumes. Copy the original `.env`, `app/etc/env.php`, and `app/etc/config.php` along with the scripts. Also copy `pub/media`, `var/sample-data`, and the sample-data module symlinks in `app/code/Magento` if you installed demo data, plus any custom modules used by the store. These local files are ignored by Git and are not included in a fresh fork or clone.

An `Access denied` error after a move usually means the new directory generated a new `.env`. Restore the original `.env`: MariaDB retains the passwords stored in its existing volume. `start.sh` checks the database login and refuses to install over a populated database when the installed configuration is missing.

## Demo data

Install the official Luma demo products, categories, images, CMS content, customers, and orders:

```bash
./demo-data.sh
```

The script starts Magento, downloads the matching `2.4-develop` sample-data branch from [Magento's official repository](https://github.com/magento/magento2-sample-data), adds the demo modules and media, backs up the database under `var/backups/`, and upgrades and reindexes the store.

Sample-data source files are kept in `var/sample-data/`. Keep this directory because the demo modules link to it. Magento records the applied data patches, so rerunning the script preserves the existing demo data. Normal restarts still use `./start.sh`.

## Database access

The database runs in the `db` Docker Compose service. Its connection details are:

| Setting | Value |
| --- | --- |
| Database engine | MariaDB 11.4 |
| Host (from other Compose containers) | `db` |
| Port (inside Docker) | `3306` |
| Database name | `magento` |
| Username | `magento` |
| Password | `MAGENTO_DB_PASSWORD` in `.env` |
| Root username | `root` |
| Root password | `MAGENTO_DB_ROOT_PASSWORD` in `.env` |

With the containers running, open a SQL console from the repository root:

```bash
docker compose exec db mariadb -u magento -p magento
```

At the password prompt, enter the `MAGENTO_DB_PASSWORD` value from `.env`.

For a root SQL console:

```bash
docker compose exec db mariadb -u root -p
```

At this password prompt, enter the `MAGENTO_DB_ROOT_PASSWORD` value from `.env`.

Type `exit` to leave the SQL console. The database port is not published to the host; use these commands to access it from your terminal.

## REST integration tests

Integration tests use the `magento2-integration` Docker Compose project, with a separate MariaDB server and database named `magento_integration`. Its Magento instance runs at `http://localhost:8081`; the interactive demo remains on port `8080`. The integration instance has its own OpenSearch server, configuration, caches, sessions, generated files, static files, and media.

When moving the checkout, also copy `var/apih-integration/environment` from the original directory. It contains the passwords for the existing integration database volume. If a new environment file was already generated, replace it with the original and rerun `./apih-tests/run.sh`. The runner refreshes the application configuration to match that file and checks database credentials before stopping the integration application or importing the snapshot.

The clean demo baseline is saved locally as [apih-tests/demo.sql](apih-tests/demo.sql), with a checksum in [demo.sql.sha256](apih-tests/demo.sql.sha256). It contains 2,046 products, one customer, and two demo orders. It was rebuilt from the original pre-demo backup by applying the installed Luma demo-data patches on the integration server. The SQL snapshot is ignored by Git.

Create the baseline once if it does not already exist:

```bash
./apih-tests/setup.sh
```

The default source backup is `var/backups/before-demo-20261013T041601Z.sql`. To use another pre-demo backup, pass its path to `setup.sh`. The installed demo configuration and `var/sample-data/` are required.

Run the tests from the repository root:

```bash
./apih-tests/run.sh
```

Before every run, the script verifies the snapshot checksum, checks database credentials, stops the integration web/PHP services, recreates only the integration database, restores `demo.sql`, clears integration caches and sessions, applies schema and data updates for the current checkout, rebuilds its indexes, and starts its API. It then runs APIHydra with default parallelism `1`. Login runs first; independent child directories run concurrently, and nested directories order the cart, checkout, and order requests. A lock prevents overlapping runs.

There is no end-of-run cleanup. The main test customer, product, and cancelled order remain available for inspection; the next run restores the clean baseline, including after an interruption. Deletion and token revocation remain explicit API behavior tests using disposable fixtures.

To restore the integration baseline without running tests:

```bash
./apih-tests/reset.sh
```

If APIHydra's default user cache is read-only:

```bash
XDG_CACHE_HOME=/tmp/magento-apih-cache ./apih-tests/run.sh
```

To stop only the integration stack:

```bash
docker compose --project-name magento2-integration \
  --env-file var/apih-integration/environment \
  -f apih-tests/compose.yaml down
```

The latest complete isolated run verified on 2026-10-14 passed all 53 steps, covering all 32 scoped operations (100%), with exit `0`; see [the checkout-move report](apih-tests/results/checkout-move.txt). The suite normalizes the payment endpoint's order ID at capture time with jq `tonumber` and validates the resulting order in subsequent requests. Interactive demo database dumps were byte-for-byte identical before and after this run.

See [coverage and run results](apih-tests/coverage.md) and [API.md](API.md#rest-integration-tests-with-apihydra) for authentication and detailed setup instructions.

## GraphQL and REST APIs

GraphQL is an API too. This Magento installation provides both GraphQL and REST APIs:

- **GraphQL** supports storefront workflows: browsing, customer accounts, carts, and checkout. Queries read data; mutations change data. The local schema exposes 27 non-deprecated queries and 59 non-deprecated mutations at http://localhost:8080/graphql.
- **REST** supports administration and integrations, including creating products, updating inventory, and managing store data. Its local base URL is `http://localhost:8080/rest/default/V1/`.

Choose the API according to the operation you need. See [API.md](API.md) for REST authentication, Swagger, and request examples, and [GRAPHQL.md](GRAPHQL.md) for GraphQL authentication and the complete list of current query and mutation signatures.
