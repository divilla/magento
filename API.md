# Accessing Magento APIs

Start Magento with `./start.sh` before making API requests. The local server runs at `http://localhost:8080`.

| API | URL |
| --- | --- |
| Interactive REST documentation | http://localhost:8080/swagger |
| REST base URL | `http://localhost:8080/rest/default/V1/` |
| GraphQL endpoint | `http://localhost:8080/graphql` |

## REST authentication

Request an admin token. Replace `YOUR_ADMIN_PASSWORD` with the `MAGENTO_ADMIN_PASSWORD` value from `.env`:

```bash
curl -sS http://localhost:8080/rest/default/V1/integration/admin/token \
  -H 'Content-Type: application/json' \
  --data '{"username":"admin","password":"YOUR_ADMIN_PASSWORD"}'
```

Copy the returned token without its surrounding quotes, then fetch five demo products:

```bash
curl -g \
  'http://localhost:8080/rest/default/V1/products?searchCriteria[pageSize]=5' \
  -H 'Authorization: Bearer YOUR_TOKEN'
```

Replace `YOUR_TOKEN` with your token. Protected REST endpoints require the `Authorization: Bearer` header.

You can also paste the token into the **Authorize** dialog at http://localhost:8080/swagger to explore and call protected endpoints. Paste only the token; Swagger adds the `Bearer` prefix.

The local REST schema is available as JSON at `http://localhost:8080/rest/default/schema?services=all`. Supply the same authorization header to retrieve the schema for the admin's accessible services:

```bash
curl -sS \
  'http://localhost:8080/rest/default/schema?services=all' \
  -H 'Authorization: Bearer YOUR_TOKEN'
```

## REST integration tests with APIHydra

Integration tests run against a separate Magento instance at `http://localhost:8081`; the interactive demo remains on `http://localhost:8080`. The integration Compose project has its own MariaDB server (`magento_integration` database), OpenSearch server, network, database/search volumes, configuration, caches, sessions, generated files, static files, and media. Application source and installed demo-data modules are mounted read-only.

The clean baseline is saved locally as [apih-tests/demo.sql](apih-tests/demo.sql), with its checksum in [demo.sql.sha256](apih-tests/demo.sql.sha256). The SQL file is ignored by Git. It was rebuilt by restoring the original pre-demo backup into the integration server and applying the installed Luma sample-data patches there. The interactive demo database was not used as the integration database or restored by these scripts.

Create the baseline once (it already exists in this workspace):

```bash
./apih-tests/setup.sh
```

The default input is `var/backups/before-demo-20261013T041601Z.sql`. To use another pre-demo backup, pass its path to `setup.sh` when `demo.sql` does not yet exist. Setup copies the demo encryption key needed by its data, creates separate database credentials under `var/apih-integration/environment`, and prepares a private Magento configuration. It enables updates on save for stock and price indexes in the integration instance so newly created stocked products are immediately purchasable, without changing the demo's indexer settings.

Run from the repository root:

```bash
./apih-tests/run.sh
```

The runner checks the snapshot checksum, stops the integration web/PHP services, recreates only `magento_integration` on the dedicated integration database server, imports `demo.sql`, clears the integration caches/sessions, rebuilds its indexes, starts its API, and then executes `apih ./apih-tests` with default parallelism `1`. A lock prevents overlapping setup/reset/test runs. It propagates APIHydra's exit code. Always use this runner for a fresh database before testing.

Login executes in the suite root. Its child directories (`catalog`, `customers`, and `store`) then run concurrently. The dependent cart, checkout, and orders directories are nested beneath `customers`, with a stage barrier before each depth. Captures have unique names across the entire run. Selecting a dependent subtree with `apih` alone does not execute its parent login/setup steps or reset the database.

Use APIHydra build `0852487055f8` or a compatible build with body, header, query, and path interpolation. On environments where its default user cache is read-only:

```bash
XDG_CACHE_HOME=/tmp/magento-apih-cache ./apih-tests/run.sh
```

The admin login body in [login.yaml](apih-tests/login.yaml) contains the existing local admin credentials, as requested. If the restored baseline's admin password changes, update this body. Created customers use the fixed test password `ApiHydraTest123!`. Tokens are captured in APIHydra's run-scoped variable store and reused through headers:

```yaml
request:
  method: GET
  path: /customers/me
  defaults:
    headers:
      Authorization: "Bearer ${customer_token}"
response:
  expected_status: 200
  expected_types:
    .id: [int]
```

Admin requests use `Authorization: "Bearer ${admin_token}"`. Customer login bodies reuse captured emails, for example `{"username":$customer_email,"password":"ApiHydraTest123!"}`. Cookies are disabled. The root defaults point exclusively to the integration URL on port `8081`.

The checkout fixture product costs EUR 12.50 after its update and has no tax class. Checkout buys two units, selects `flatrate_flatrate` (EUR 10 shipping), and pays with `checkmo` (EUR 35 total). The suite tests cart changes and order cancellation. Product/customer deletion and token revocation remain explicit API behavior tests using separate disposable fixtures; there is no end-of-run cleanup stage. The main customer, product, and cancelled order remain in the integration database for inspection. The next run resets everything from the baseline, including after an interruption.

The email-availability endpoint returns `true` even for registered emails when `checkout/options/enable_guest_checkout_login` is disabled, which is the baseline configuration. The suite asserts this configured behavior.

The latest verified run passed all 53 steps with exit `0`, covering all 32 scoped operations. The payment endpoint's order ID is converted at capture time using `order_id: tonumber`. This stores a JSON number, so unquoted `$order_id` preserves its numeric type in expected-response bodies and also works in paths and filters. The incoming response's primitive integer-type assertion is omitted; subsequent requests validate the normalized order ID, customer, totals, and cancellation. See [coverage and verified results](apih-tests/coverage.md) for the operation inventory and run report.

### Resetting or stopping the integration instance

To restore the baseline without running tests:

```bash
./apih-tests/reset.sh
```

To stop only the integration stack while preserving its volumes and snapshot:

```bash
docker compose --project-name magento2-integration \
  --env-file var/apih-integration/environment \
  -f apih-tests/compose.yaml down
```

No manual fixture recovery is needed. Use `run.sh` or `reset.sh` after an interrupted run; both replace only the isolated integration database. The original demo stack remains running.

## GraphQL

Public catalog queries work without authentication. For example:

```bash
curl http://localhost:8080/graphql \
  -H 'Content-Type: application/json' \
  --data '{"query":"{ products(search: \"shirt\", pageSize: 5) { total_count items { sku name } } }"}'
```

## Official documentation

- [REST API reference](https://developer.adobe.com/commerce/webapi/rest/reference/) — select the **PaaS** reference for this Magento Open Source installation.
- [Local Swagger and REST schema instructions](https://developer.adobe.com/commerce/webapi/rest/quick-reference/generate-local)
- [GraphQL API reference](https://developer.adobe.com/commerce/webapi/graphql/reference/)
- [GraphQL overview](https://developer.adobe.com/commerce/webapi/graphql/)
- [Authentication guide](https://developer.adobe.com/commerce/webapi/get-started/authentication/)
- [Token-based authentication](https://developer.adobe.com/commerce/webapi/get-started/authentication/gs-authentication-token)

The admin-token endpoint shown above was verified against this local source installation. Installations with two-factor authentication enabled use the corresponding provider authentication endpoints described in the authentication documentation.
