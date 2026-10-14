# Magento REST operation coverage

Verified on 2026-10-14 against the isolated integration instance at `http://localhost:8081/rest/default/V1`, using default parallelism `1`. The latest run from the moved checkout passed all 53 request steps with exit `0`; see [the checkout-move report](results/checkout-move.txt). The interactive demo database dumps were identical before and after this run.

## Scope and result

The fixed scope is 32 selected core REST method/route pairs. The authenticated integration schema at `/rest/default/schema?services=all` exposes **348 enabled operations**. The other 316 operations, GraphQL, and asynchronous/bulk APIs are outside this scope. This measures API operation coverage, not source line or branch coverage.

- Attempted: **32/32 operations**, with **53 request steps**.
- Passing: **32/32 = 100%** scoped coverage, above the 90% minimum of 29 operations.
- Coverage across all enabled REST operations: **32/348 = 9.20%**.
- Latest complete run: **53/53 steps passed**, exit **0**; see [the verified report](results/checkout-move.txt).
- The payment-ID primitive integer assertion is omitted by the accepted workaround; the resulting order is validated by dependent requests.

## Database isolation and baseline

[compose.yaml](compose.yaml) creates a dedicated MariaDB server, OpenSearch server, Docker network, database/search volumes, and PHP/web services under project `magento2-integration`. The database is always `magento_integration`; it is not a second schema on the demo MariaDB server. The integration API listens on loopback port `8081`; the interactive demo stays on port `8080`. Runtime configuration, caches, sessions, generated files, static assets, and media are private to `var/apih-integration/`. Shared application source and installed sample-data modules are read-only.

[setup.sh](setup.sh) rebuilt the original demo from `var/backups/before-demo-20261013T041601Z.sql`, applying the installed Luma sample-data patches only on the integration server. It saved [demo.sql](demo.sql), a local 13,789,739-byte snapshot with mode `0600`, and [its checksum](demo.sql.sha256). The SQL snapshot is ignored by Git. SQL trigger definers are rebound to the integration database account. Integration configuration points to its own database/search server and URL. Stock and price indexes update on save in the integration baseline.

Baseline: **2,046 products, one customer, two demo orders, and no APIHydra fixtures**. The earlier test orders from the interactive demo were not copied into this baseline.

```bash
./apih-tests/run.sh
```

The runner verifies the snapshot checksum, refreshes integration configuration, checks database credentials, stops only integration web/PHP, recreates only the integration database, imports `demo.sql`, clears integration caches/sessions, applies schema and data updates for the current checkout, rebuilds integration indexes, starts the API, waits for readiness, and immediately runs `apih ./apih-tests`. A lock rejects overlapping setup/reset/runs. The wrapper propagates APIHydra's exit code and uses its default parallelism `1`. The verified sandbox invocation was `XDG_CACHE_HOME=/tmp/magento-apih-cache ./apih-tests/run.sh`.

There is **no cleanup stage**. The main created product, customer, and cancelled order remain for inspection. Product/customer deletion and token revocation are API behavior checks using separate disposable fixtures. Every subsequent run restores the baseline, including after interruptions. To reset without testing, run [reset.sh](reset.sh). See [setup and rerun instructions](../API.md#rest-integration-tests-with-apihydra).

## Directory stages

```text
apih-tests/                                      stage 0: login.yaml + root.yaml
├── store/                                       stage 1: configuration and missing auth
├── catalog/                                     stage 1: catalog/product behavior
└── customers/                                   stage 1: customer/authentication behavior
    └── cart/                                    stage 2: cart lifecycle
        └── checkout/                            stage 3: shipping, totals, payment
            └── orders/                          stage 4: order reads and cancellation
```

Root login completes before its child directories run concurrently. The full stage-1 barrier makes the catalog product capture available to cart. Later depths wait for the preceding stage; steps inside every file execute serially. No request depends on a capture from a concurrent sibling in the same stage.

## Operation inventory and test mapping

Route templates below come from the enabled integration schema and are relative to `/rest/default`. Indices are zero-based `spec.steps` positions; the IDs appear as comments above each request. Operations count as passing after explicit HTTP status and meaningful body/predicate/type checks, including dependent workflow checks of captured response values. The payment-ID primitive type exception is documented below. Negative cases supplement success requests.

| Method | Route template | Tests (file and zero-based index) | Current run |
| --- | --- | --- | --- |
| GET | `/V1/carts/mine` | [CART-02](customers/cart/cart.yaml) [1] | PASS |
| POST | `/V1/carts/mine` | [CART-01](customers/cart/cart.yaml) [0] | PASS |
| POST | `/V1/carts/mine/estimate-shipping-methods` | [CHECKOUT-01](customers/cart/checkout/checkout.yaml) [0] | PASS |
| GET | `/V1/carts/mine/items` | [CART-04](customers/cart/cart.yaml) [3], [CART-06](customers/cart/cart.yaml) [5], [CART-08](customers/cart/cart.yaml) [7] | PASS |
| POST | `/V1/carts/mine/items` | [CART-03](customers/cart/cart.yaml) [2], [CART-09](customers/cart/cart.yaml) [8] | PASS |
| DELETE | `/V1/carts/mine/items/{itemId}` | [CART-07](customers/cart/cart.yaml) [6] | PASS |
| PUT | `/V1/carts/mine/items/{itemId}` | [CART-05](customers/cart/cart.yaml) [4] | PASS |
| POST | `/V1/carts/mine/payment-information` | [CHECKOUT-05](customers/cart/checkout/checkout.yaml) [4] | PASS |
| GET | `/V1/carts/mine/payment-methods` | [CHECKOUT-03](customers/cart/checkout/checkout.yaml) [2] | PASS |
| POST | `/V1/carts/mine/shipping-information` | [CHECKOUT-02](customers/cart/checkout/checkout.yaml) [1] | PASS |
| GET | `/V1/carts/mine/totals` | [CHECKOUT-04](customers/cart/checkout/checkout.yaml) [3] | PASS |
| POST | `/V1/customers` | [CUSTOMER-02](customers/customers.yaml) [1], [CUSTOMER-03](customers/customers.yaml) [2], [CUSTOMER-05](customers/customers.yaml) [4] | PASS |
| POST | `/V1/customers/isEmailAvailable` | [CUSTOMER-01](customers/customers.yaml) [0], [CUSTOMER-04](customers/customers.yaml) [3] | PASS |
| GET | `/V1/customers/me` | [CUSTOMER-08](customers/customers.yaml) [9], [CUSTOMER-10](customers/customers.yaml) [11], [CUSTOMER-12](customers/customers.yaml) [13], [CUSTOMER-14](customers/customers.yaml) [15] | PASS |
| PUT | `/V1/customers/me` | [CUSTOMER-09](customers/customers.yaml) [10] | PASS |
| GET | `/V1/customers/search` | [CUSTOMER-06](customers/customers.yaml) [5] | PASS |
| DELETE | `/V1/customers/{customerId}` | [CUSTOMER-15](customers/customers.yaml) [16] | PASS |
| GET | `/V1/customers/{customerId}` | [CUSTOMER-07](customers/customers.yaml) [6], [CUSTOMER-11](customers/customers.yaml) [12], [CUSTOMER-16](customers/customers.yaml) [17] | PASS |
| POST | `/V1/integration/admin/token` | [AUTH-01](login.yaml) [0], [AUTH-02](login.yaml) [1] | PASS |
| POST | `/V1/integration/customer/revoke-customer-token` | [CUSTOMER-13](customers/customers.yaml) [14] | PASS |
| POST | `/V1/integration/customer/token` | [AUTH-03](customers/customers.yaml) [7], [AUTH-04](customers/customers.yaml) [8] | PASS |
| GET | `/V1/orders` | [ORDER-02](customers/cart/checkout/orders/orders.yaml) [1] | PASS |
| GET | `/V1/orders/{id}` | [ORDER-01](customers/cart/checkout/orders/orders.yaml) [0], [ORDER-06](customers/cart/checkout/orders/orders.yaml) [5] | PASS |
| POST | `/V1/orders/{id}/cancel` | [ORDER-04](customers/cart/checkout/orders/orders.yaml) [3] | PASS |
| GET | `/V1/orders/{id}/statuses` | [ORDER-03](customers/cart/checkout/orders/orders.yaml) [2], [ORDER-05](customers/cart/checkout/orders/orders.yaml) [4] | PASS |
| GET | `/V1/products` | [CAT-05](catalog/products.yaml) [4], [CAT-08](catalog/products.yaml) [7] | PASS |
| POST | `/V1/products` | [CAT-02](catalog/products.yaml) [1], [CAT-07](catalog/products.yaml) [6], [CAT-09](catalog/products.yaml) [8] | PASS |
| GET | `/V1/products/attribute-sets/sets/list` | [CAT-01](catalog/products.yaml) [0] | PASS |
| DELETE | `/V1/products/{sku}` | [CAT-10](catalog/products.yaml) [9] | PASS |
| GET | `/V1/products/{sku}` | [CAT-03](catalog/products.yaml) [2], [CAT-06](catalog/products.yaml) [5], [CAT-11](catalog/products.yaml) [10] | PASS |
| PUT | `/V1/products/{sku}` | [CAT-04](catalog/products.yaml) [3] | PASS |
| GET | `/V1/store/storeConfigs` | [STORE-01](store/store.yaml) [0], [STORE-02](store/store.yaml) [1] | PASS |

## Behavioral coverage

Verified cases include invalid admin login; missing authentication; denial of customer access to another customer; isolation of `/customers/me`; invalid email/product payloads; missing and deleted resources; exact search filtering and pagination including an empty second product page; product updates and deletion; customer updates and deletion; token revocation followed by rejection; empty carts, item quantity changes, deletion and re-addition; available flat-rate shipping; EUR 25 subtotal, EUR 10 shipping, and EUR 35 grand total; and pending-to-canceled orders with two canceled units.

The baseline disables `checkout/options/enable_guest_checkout_login`. `Customer/Model/AccountManagement.php::isEmailAvailable` therefore returns `true` even for existing emails; the suite asserts that configured behavior.

## Order-ID workaround

The installed payment endpoint returns its order ID as a JSON string, while the interface and schema describe an integer. The accepted workaround normalizes the response at capture time with `order_id: tonumber` and omits the primitive integer assertion on the incoming `CHECKOUT-05` response. The stored value is a JSON number; unquoted `$order_id` preserves its numeric type in expected-response bodies and also supplies its text value in paths and filters. Subsequent order reads validate the captured ID, customer, totals, payment/shipping methods, and cancellation; the final order read also asserts integer `.entity_id`.

The current suite passes all 53 steps. The earlier strict-type runs are retained below as historical results; they do not describe the current suite outcome.

## Repeatability and demo protection evidence

| Historical run (before workaround) | Restored starting counts (products/customers/orders) | Passing steps | Exit | Retained test order | Ending counts |
| --- | --- | --- | --- | --- | --- |
| [Run 1](results/run1.txt) | 2046 / 1 / 2 | 52/53 | 101 | 3, `canceled`, two canceled units | 2047 / 2 / 3 |
| [Run 2](results/run2.txt) | 2046 / 1 / 2 | 52/53 | 101 | 3, `canceled`, two canceled units | 2047 / 2 / 3 |

The latest [numeric-capture run](results/number-capture.txt) restored starting counts of 2046 / 1 / 2 and passed 53/53 steps with exit `0`. The preceding [interpolation-workaround run](results/workaround.txt) also passed 53/53 steps.

Each earlier run retained one main test product and one main test customer. The second run's reused order ID and restored starting counts confirm that the first run's data was discarded before testing. A database query after run 2 confirmed the first run's exact product SKU was absent. Full state queries are recorded in [isolation results](results/isolation.txt).

The original demo database was dumped before setup and after both runs using identical `mariadb-dump --single-transaction --skip-comments` options. The files are byte-for-byte identical and have SHA-256:

```text
c7b5cf9b3e3663d769728079ef9277f21a56555d570878284d8c809162e7d5fb
```

The demo uses volume `magento2-local_db-data` and network `magento2-local_default`. Integration uses volume `magento2-integration_integration-db-data` and network `magento2-integration_default`. No original demo database, indexer setting, or application configuration was changed during this migration or either isolated run. This comparison starts before the migration; earlier tests from the previous suite version had already left cancelled orders in the demo. Issued tokens are absent from these reports.
