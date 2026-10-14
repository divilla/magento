# Magento API compatibility suite, split by domain

## Summary

Expand the existing APIHydra suite into a portable compatibility specification for the Go/PostgreSQL rewrite.

Work **breadth first**: cover every feasible synchronous REST operation, then deepen behavioral coverage. The initial inventory is **344 operations**, excluding four bulk-status operations deferred with async/bulk. Aim for 100%; 90% means at least **310 passing operations** and is a checkpoint, not the stopping point.

## Task breakdown

Each numbered row is a separate implementation task. Extend existing tests wherever applicable.

| Task | API group | Main coverage |
|---|---|---|
| 01 | Suite foundation | Complete operation inventory, group ownership, dependency mapping, selectable runner, portable fixture requirements |
| 02 | Authentication and platform | Admin/customer tokens, revocation, stores, websites, countries, currencies, modules |
| 03 | Customer accounts | Create, read, update, validate, passwords, activation, confirmation, recovery |
| 04 | Customer supporting APIs | Addresses, default billing/shipping, customer groups, permissions, attribute metadata |
| 05 | Catalog attributes | Product attributes, options, attribute sets/groups, generic EAV operations |
| 06 | Categories and search | Category CRUD, hierarchy/moves, product assignments, search |
| 07 | Basic products | Product CRUD, types, render information, links, website assignments |
| 08 | Product pricing | Base, special, tier/group prices, costs, retrieval and deletion |
| 09 | Product media and options | Media entries, custom options, option/media type metadata |
| 10 | Configurable products | Variations, options, child assignment and removal |
| 11 | Bundle products | Options, children, links, updates and removal |
| 12 | Downloadable products | Download links and samples |
| 13 | Inventory | Stock items, stock status, quantity updates, low-stock listing |
| 14 | CMS | Pages and blocks: CRUD and search |
| 15 | Tax | Classes, rates, rules, search |
| 16 | Promotions | Sales rules, coupons, generation and bulk deletion |
| 17 | Admin carts and checkout | Cart creation/search, customer assignment, items, addresses, shipping, totals, payment, coupons, gift messages, placement |
| 18 | Customer carts and checkout | Corresponding `/carts/mine` operations, including cart assignment and totals collection |
| 19 | Guest carts and checkout | Corresponding `/guest-carts` operations, masked IDs and customer assignment |
| 20 | Checkout agreements | Agreement listing and applicable checkout enforcement |
| 21 | Orders | Reads/search, items, updates, comments, status, hold/unhold, cancellation, email requests |
| 22 | Invoices | Creation, reads/search, comments, capture, void, email requests |
| 23 | Shipments | Creation, reads/search, comments, tracking, labels, email requests |
| 24 | Refunds | Credit memos, order/invoice refunds, comments, updates, email requests |
| 25 | Integration-dependent remainder | Transactions, analytics, and unresolved provider-dependent scenarios |
| 26 | Behavioral depth | Cross-domain pricing, tax, discount, inventory and fulfillment scenarios; security and boundary cases |
| 27 | Rewrite handoff | Portable suite package, baseline requirements, compatibility exceptions, final coverage and rerun instructions |

**Execution order:** 01–02 first; 03–16 next; 17–20 after their customer/catalog/tax/promotion prerequisites; 21–25 after order-producing workflows; 26–27 last. Each task declares its exact prerequisites in the inventory.

## Fresh context for each task

Implement each numbered task in a separate fresh Codex chat/task in the same repository. Carry continuity through repository files rather than the previous conversation. Complete one task and its handoff before starting the next; do not run tasks concurrently against the shared workspace or integration instance.

1. Start a new chat/task without inheriting the previous transcript. The automatic runner below starts a fresh `codex exec` session for every task and retry. For manual execution, use `/new` or `/clear` after the preceding task finishes. `/compact` retains a summary and does not provide a fresh context; forking also retains conversation history.
2. Read this plan, `APIH-REST-PROGRESS.md`, applicable repository instructions, and the APIHydra skill. Inspect the relevant implementation, tests, and current workspace changes. Verify prerequisites against the repository before making changes.
3. Implement only the selected task and the prerequisite fixes necessary to validate it. Preserve unrelated changes and follow the shared implementation rules below.
4. Run the required focused and accumulated-suite checks. Update `apih-tests/coverage.md` with verified results and gaps.
5. Update `APIH-REST-PROGRESS.md` before ending the task, including after an interruption or blocker. Record enough information for a fresh task to resume without reading the previous chat.
6. End the task with a concise result and identify the next eligible task. Start that task with fresh context and repeat this process. Skip blocked dependent tasks until their prerequisites are satisfied; independent tasks may continue.

Task 01 creates `APIH-REST-PROGRESS.md` in the repository root. Keep it concise, with a status table for tasks 01–27 (`pending`, `in progress`, `complete`, or `blocked`) and short handoff notes covering:

- Changes made and relevant file paths.
- Validation commands, outcomes, report locations, and measured coverage.
- Fixture/configuration requirements and accepted compatibility exceptions.
- Blockers, unfinished work, and the next eligible task with its prerequisites.

Keep credentials and tokens out of the progress file. Link detailed reports instead of copying logs or debugging history. Mark a task complete only when its applicable completion criteria are met; record partial results explicitly.

Use this starting prompt, replacing `NN` with the selected task number:

```text
Implement task NN from APIH-REST-PLAN.md in this fresh task. Read
APIH-REST-PROGRESS.md first if it exists; task 01 must create it. Follow
applicable repository instructions and the APIHydra skill, verify prerequisites,
preserve existing changes, run the required checks, and update progress and
coverage before finishing. Stop after this task and identify the next eligible
task for a fresh chat.
```

## Automatic execution

Run the entire plan from the repository with:

```bash
./exec-plan.sh
```

The Bash runner executes tasks 01–27 sequentially, with one fresh, ephemeral `codex exec` session per task. It reads prompts from standard input, requires structured final results, and uses `--approve-for-me` for workspace sandboxing with automatic approval review. It inherits the configured model unless `--model` is supplied. Codex must already be authenticated; the runner also requires `jq`, `flock`, and `sha256sum`.

- Task 01 creates the progress file. Its status table must use `Task` and `Status` as its first two columns, two-digit task IDs, and plain status values. Every task verifies its prerequisites and updates its own handoff before returning.
- A task advances only when Codex exits successfully, its structured result reports completion and passing checks, and its progress row is `complete`. The runner checks these records; the task agent performs the actual validation.
- Failed executions or incomplete results receive up to two fresh-session attempts by default. After those attempts, the runner stops with exit code `1`; partial edits remain available for inspection and recovery.
- A blocked task with a recorded handoff is retained as blocked and later tasks are attempted, checking their own prerequisites. A blocked task 01 stops the run because the foundation is required. Use `--stop-on-blocked` to stop at any blocker. A run with blocked tasks exits `2`.
- Re-running the script skips tasks whose completion checkpoint and progress row agree, provided the plan has not changed. Pending, interrupted, failed, or blocked tasks are attempted again. Changes to the plan invalidate saved completion checkpoints; agents then verify the existing implementation and checks.
- Private prompts, event logs, diagnostics, and structured results are stored in Git-ignored `var/apih-plan-exec/`. Keep the concise progress file as the primary handoff. The runner prevents overlapping runs of itself; do not run another implementation agent or integration test runner concurrently.
- Exit code `0` means all tasks in the selected range are complete. No tasks commit or push changes, launch other Codex sessions, or implement subsequent tasks; the Bash runner controls sequencing.

Useful commands:

```bash
./exec-plan.sh --dry-run               # Preview all prompts without invoking Codex
./exec-plan.sh --from 08 --to 12       # Run a selected range, verifying prerequisites
./exec-plan.sh --attempts 3           # Allow three fresh-session attempts per task
./exec-plan.sh --help
```

## Shared implementation rules

- Task 01 assigns every in-scope method/route pair to exactly one owning group and maps the existing 32 covered operations. Keep blocked operations in the denominator.
- Extend the runner to select groups and automatically include their prerequisite tests in the same APIHydra invocation. Use serial execution initially and preserve required stage ordering.
- Create mutable fixtures through APIs, capture generated IDs, and use unique capture names. Discover baseline identifiers instead of assuming database IDs.
- Keep Magento reset/setup scripts separate from reusable HTTP tests. Document the baseline configuration the PostgreSQL implementation must reproduce; implementing its reset adapter is outside this task.
- Add local email capture and integration-only configuration for account and notification flows. Use locally configured payment/shipping methods; record external-provider requirements precisely.
- Assert verified Magento behavior, stable values, response types, and state changes. Document quirks and preserve existing accepted exceptions; introduce no silent normalization or weakened assertions.
- Preserve current workspace changes. This work changes tests, runners, local test infrastructure and documentation; it does not change Magento’s public application APIs.

## Completion and validation

Every domain task delivers:

- Tests for its operations with explicit status and meaningful response assertions, including successful behavior where feasible.
- Relevant validation, authentication/ownership and missing-resource cases.
- A passing focused run including prerequisites, followed by the complete accumulated suite.
- Updated operation mappings, measured coverage, behavioral gaps and concrete blockers in `apih-tests/coverage.md`.

Authentication rejection alone does not establish functional coverage of a protected operation. Distinguish fully verified operations from partially exercised or blocked ones.

Task 26 adds compound scenarios: taxed and discounted checkout, insufficient stock, variant/bundle purchases, partial fulfillment/refunds, invalid transitions, pagination/filtering and cross-customer isolation.

Task 27 runs the complete suite twice from fresh baselines, measures final PHP coverage separately, and verifies that portable tests contain no Magento SQL dependencies. Measure PHP coverage additionally after the catalog, checkout and fulfillment milestones to identify unexplored behavior.

## Assumptions

Synchronous REST comes first; GraphQL and async/bulk receive later plans. Observed Magento behavior is the compatibility reference. Local supporting services are allowed; unavailable external providers remain documented gaps. All execution targets the isolated integration instance.
