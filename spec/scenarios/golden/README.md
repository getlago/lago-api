# Golden billing suite

A characterization suite for Lago's billing behaviour, written as **data rather than code**: each
case is a YAML row saying *set this up, do these things at these times, expect exactly this*. A
generic interpreter turns every row into an RSpec example driving the real REST API.

Two things make it different from `spec/scenarios/` around it:

1. **Coverage is computed, not guessed.** The suite knows how many cells exist, how many are covered,
   and which are missing — see COVERAGE.md, a build product of `rake golden:docs` (generated
   docs are not committed; run the task to produce them).
2. **Adding coverage means adding a row, not writing Ruby.**

> This suite is generated and maintained by the `golden-billing` skill, which audits coverage,
> discovers new behaviour, proposes rows, and triages failures. The suite does not depend on it:
> the rows and the RSpec driver are plain data and plain Ruby, and run in CI with no model in the
> loop. The skill maintains the suite; it is not required to execute it.

## Contents

- [Why it exists](#why-it-exists) · [Running it](#running-it) · [What lives where](#what-lives-where)
- [How coverage is measured](#how-coverage-is-measured) — [the 16 blocks](#the-16-blocks),
  [legality tables](#legality-what-lago-actually-permits), [actions](#action-coverage)
- [Row schema](#row-schema) — [setup](#setup), [timeline](#timeline), [expectations](#expectations)
- [Results: what a run emits](#results-what-a-run-emits) — [the run report](#the-run-report),
  [discovering new behaviour](#discovering-new-behaviour)
- [The guardrail](#the-guardrail) · [Known traps](#known-traps)
- [Two kinds of remaining work](#two-kinds-of-remaining-work) · [Not built yet](#not-built-yet)

---

## Why it exists

The existing scenario suite grew one-spec-per-bug: 126 files, ~44k lines, no map. Measuring it
turned up a specific, uncomfortable shape.

**Usage is far better covered than invoices.** Counting spec files by the dimension they exercise,
split by whether they assert an invoice or only current usage:

> **Correction.** This table classifies specs by DIRECTORY, and that is wrong at the edges: several
> specs living under `current_usage/` do assert invoices. `by_aggregation_type/weighted_sum_agg_spec.rb:60`
> asserts `fee.amount_cents == 217_742` on a real invoice, so the "0 invoice files" reading for
> `weighted_sum_agg` was a classification artefact, not a gap. The broad shape — `standard`/`sum_agg`
> dominating, tiered models and rarer aggregations thin — holds. The precise zeroes do not. Treat the
> table as a shape, not a census.

| dimension | invoice | usage-only |
|---|---:|---:|
| standard | 63 | 12 |
| graduated | 4 | 4 |
| package | 4 | 2 |
| percentage | 1 | 2 |
| **volume** | **0** | 2 |
| graduated_percentage | 1 | 2 |
| **custom** | **0** | 1 |
| dynamic | 1 | 1 |
| sum_agg | 50 | 11 |
| **max_agg** | **0** | 2 |
| **weighted_sum_agg** | **0** | 1 |
| **custom_agg** | **0** | 1 |

`Invoices::CustomerUsageService` and `Fees::ChargeService` → `Invoices::CalculateFeesService` are
different code paths, and the usage one carries 12 fix commits of its own — which is reason enough
for `observed_via` to be an axis of B1, independently of the miscounted zeroes above.

Intervals are just as lopsided: monthly 45 files, yearly 9, weekly 2, quarterly 2, semiannual 2.
`rounding_function` has **zero** scenario coverage — tested only at the controller and serializer
level, never through a fee.

**Hand-built grids drift.** `spec/scenarios/commitments/minimum/` is already a deliberate
`in_advance|in_arrears × calendar|anniversary × weekly|monthly|quarterly|yearly` grid, 16 files. It
is missing `semiannual` entirely and nobody noticed, because nothing computed the product. That is
why legal cells here are **derived from Lago's own constants and validators** rather than declared —
block B12 reports 20 cells against those 16 files, and names the four gaps.

**Bug provenance was lost.** Exactly one ticket id appears anywhere in `spec/scenarios/` (ING-13).
Every golden row therefore carries a mandatory `provenance:` field.

---

## Running it

```bash
dev/golden/run.sh rspec spec/scenarios/golden
```

```bash
dev/golden/run.sh rake golden:ledger
```

```bash
dev/golden/run.sh rake golden:docs
```

Narrowing — the example name is the row id, so any prefix works:

```bash
dev/golden/run.sh rspec spec/scenarios/golden -e "b01/volume"
```

`run.sh` runs natively inside the api container or on CI and re-enters docker from a host, and sets
`LAGO_DISABLE_SCHEMA_DUMP=true`, without which the run rewrites `db/structure.sql`. The `annotate`
gem touches `app/models/*.rb` on every run regardless — check `git status` before staging after a run.

Refresh the risk column on the **host** (not the container — `api` is a submodule whose real `.git`
is not mounted):

```bash
ruby dev/golden/bugmap.rb
```

The full report — three sections, a proposal, and nothing written — also runs on the host, because
the ①/② split needs git:

```bash
ruby dev/golden/report.rb
```

```bash
ruby dev/golden/report.rb --block B6
```

```bash
ruby dev/golden/report.rb --mark-green
```

Behaviour-surface tasks:

```bash
dev/golden/run.sh rake golden:discover
```

```bash
dev/golden/run.sh rake golden:surface
```

Denominator-baseline tasks — what the daily surveyor uses to answer "which cells are new":

```bash
dev/golden/run.sh rake golden:delta
```

```bash
dev/golden/run.sh rake golden:baseline
```

---

## What lives where

| path | kind | what |
|---|---|---|
| `matrix/*.yml` | data | the rows — one file per block |
| `blocks.yml` | data | block definitions: axes, constraints, owning services |
| `actions.yml` | data | which controllers count towards action coverage |
| `schema.json` | contract | the row contract, enforced as its own spec example |
| `bugmap.json` | generated | fix-commit counts per block, produced on the host |
| `surface.json` | generated | the recorded behaviour-surface baseline that `discover` diffs against |
| `baseline.yml` | generated | the recorded denominator baseline that `golden:delta` diffs against |
| `COVERAGE.md` | generated | the summary — a `rake golden:docs` build product, not committed |
| `golden_spec.rb` | code | turns each row into an example |
| `legality_spec.rb` | code | proves derived legality matches Lago's real validations |
| `../../support/golden_runner.rb` | code | the step interpreter |
| `../../support/golden_matrix.rb` | code | loader + lints |
| `../../support/golden_legality.rb` | code | derived domains and constraint predicates |
| `../../support/golden_ledger.rb` | code | coverage and action arithmetic |
| `../../../lib/tasks/golden.rake` | code | `golden:ledger`, `golden:docs`, `golden:surface`, `golden:discover`, `golden:state`, `golden:baseline`, `golden:delta` |
| `../../support/golden_surface.rb` | code | captures and diffs the behaviour surface |
| `../../../dev/golden/bugmap.rb` | code | host-side fix-commit counter |
| `../../../dev/golden/report.rb` | code | host-side three-section run report |

---

## How coverage is measured

**Per block, against that block's own axis product — never against a global cross-product.** The
global product is ~5,000 cells and permanently ~2% covered, which tells you nothing. Per-block
products are 10–120 cells, and each can honestly reach 100%.

An axis domain is either derived from a model constant, or declared for things Lago does not
enumerate:

```yaml
charge_model: {domain: charge_models}          # Charge::CHARGE_MODELS
aggregation:  {domain: aggregations}           # BillableMetric::AGGREGATION_TYPES
observed_via: {values: [invoice, current_usage]}
```

Because the derived domains come from constants, **the denominator grows by itself.** Add a charge
model and its cells appear as uncovered on the next ledger run, instead of the existing percentage
quietly becoming a lie.

Derived domains available to `domain:`:

| domain | source constant |
|---|---|
| `charge_models` | `Charge::CHARGE_MODELS` |
| `aggregations` | `BillableMetric::AGGREGATION_TYPES` |
| `intervals` | `Plan::INTERVALS` |
| `billing_times` | `Subscription::BILLING_TIME` |
| `fee_types` | `Fee::FEE_TYPES` |
| `invoice_types` | `Invoice::INVOICE_TYPES` |
| `on_termination_credit_notes` | `Subscription::ON_TERMINATION_CREDIT_NOTES` |
| `on_termination_invoices` | `Subscription::ON_TERMINATION_INVOICES` |
| `regroup_paid_fees_options` | `Charge::REGROUPING_PAID_FEES_OPTIONS` |
| `fixed_charge_models` | `FixedCharge::CHARGE_MODELS` |
| `wallet_transaction_sources` | `WalletTransaction::SOURCES` |
| `wallet_transaction_statuses` | `WalletTransaction::TRANSACTION_STATUSES` |
| `coupon_types` | `Coupon::COUPON_TYPES` |
| `coupon_frequencies` | `Coupon::FREQUENCIES` |
| `credit_note_types` | `CreditNote::TYPES` |
| `credit_note_reasons` | `CreditNote::REASON` |

### The 16 blocks

`constraint` names a `GoldenLegality` predicate that filters the raw product down to what Lago
permits. Where it is `—`, every combination is reachable.

| Block | Title | Axes (size) | Constraint | Raw | Legal |
|---|---|---|---|---:|---:|
| B1 | Pricing grid | `charge_model` (8) × `aggregation` (7) × `observed_via` (2) | charge_model_x_aggregation | 112 | 70 |
| B2 | Period boundaries | `interval` (5) × `billing_time` (2) × `phase` (4) | — | 40 | 40 |
| B3 | Pay-in-advance & non-invoiceable | `charge_model` (8) × `aggregation` (7) × `invoicing` (3) | pay_in_advance_charge | 168 | 48 |
| B4 | Draft lifecycle | `operation` (6) × `context` (4) | — | 24 | 16 |
| B5 | Progressive billing | `threshold` (3) × `crossing` (3) × `settlement` (3) | — | 27 | 27 |
| B6 | Wallets & prepaid credits | `source` (6) × `limitation` (4) × `application` (6) | — | 144 | 144 |
| B7 | Usage surfaces | `surface` (4) × `aggregation` (7) × `timing` (4) | — | 112 | 96 |
| B8 | Credit notes | `origin` (4) × `credit_note_type` (3) × `invoice_state` (4) | — | 48 | 48 |
| B9 | Subscription lifecycle | `transition` (8) × `plan_pay_in_advance` (2) × `on_termination_credit_note` (5) | subscription_lifecycle | 80 | 48 |
| B10 | Discounts & taxes ordering | `coupon_type` (2) × `coupon_frequency` (3) × `tax_level` (8) | — | 48 | 48 |
| B11 | Plan & charge overrides / cascade | `operation` (7) × `target` (3) | — | 21 | 21 |
| B12 | Commitments & spending minimums | `commitment_mode` (2) × `billing_time` (2) × `interval` (5) | — | 20 | 20 |
| B13 | Fixed charges | `charge_model` (3) × `pay_in_advance` (2) × `prorated` (2) × `units_change` (4) | fixed_charge | 48 | 36 |
| B14 | Constraints & negative contract | `rule` (21) | — | 21 | 21 |
| B15 | Cross-block interactions | `interaction` (10) | — | 10 | 10 |
| B16 | Proration | `charge_model` (8) × `aggregation` (7) × `pay_in_advance` (2) | prorated_charge | 112 | 8 |

**706 legal cells**, after subtracting 60 that are model-legal but unreachable through the REST API (see below). Each block's `why` — the evidence for its existence — is in `blocks.yml` and
reproduced in COVERAGE.md.

### Legality: what Lago actually permits

These tables are generated from `GoldenLegality` and verified against real `Charge` validation by
`legality_spec.rb`, which builds all 56 charge_model × aggregation cells as actual records in four
flag configurations — 224 comparisons — and fails if any predicate disagrees.

**`charge_model` × `aggregation`** — the base product. `dynamic` requires `sum_agg`
(`Charge#validate_dynamic`), `custom` requires `custom_agg` (`#validate_custom`), and `percentage` /
`graduated_percentage` reject `latest_agg` (their validators). `graduated_percentage` is legal but
licence-gated, so rows covering it set `premium: true`.

| charge model | count_agg | sum_agg | max_agg | unique_count_agg | weighted_sum_agg | latest_agg | custom_agg | legal |
|---|---|---|---|---|---|---|---|---:|
| `standard` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | 7 |
| `graduated` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | 7 |
| `package` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | 7 |
| `percentage` | ✓ | ✓ | ✓ | ✓ | ✓ | · | ✓ | 6 |
| `volume` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | 7 |
| `graduated_percentage` | ✓ | ✓ | ✓ | ✓ | ✓ | · | ✓ | 6 |
| `custom` | · | · | · | · | · | · | ✓ | 1 |
| `dynamic` | · | ✓ | · | · | · | · | · | 1 |
| **total** | | | | | | | | **42** |

**`pay_in_advance: true`** — `Charge#validate_pay_in_advance` rejects every `volume` charge, and any
metric outside `AGGREGATION_TYPES_PAYABLE_IN_ADVANCE`.

| charge model | count_agg | sum_agg | max_agg | unique_count_agg | weighted_sum_agg | latest_agg | custom_agg | legal |
|---|---|---|---|---|---|---|---|---:|
| `standard` | ✓ | ✓ | · | ✓ | · | · | ✓ | 4 |
| `graduated` | ✓ | ✓ | · | ✓ | · | · | ✓ | 4 |
| `package` | ✓ | ✓ | · | ✓ | · | · | ✓ | 4 |
| `percentage` | ✓ | ✓ | · | ✓ | · | · | ✓ | 4 |
| `volume` | · | · | · | · | · | · | · | 0 |
| `graduated_percentage` | ✓ | ✓ | · | ✓ | · | · | ✓ | 4 |
| `custom` | · | · | · | · | · | · | ✓ | 1 |
| `dynamic` | · | ✓ | · | · | · | · | · | 1 |
| **total** | | | | | | | | **22** |

**`prorated: true`, recurring metric, pay in arrears** — `Charge#validate_prorated`. `weighted_sum_agg`
is always rejected (it already prorates); a non-recurring metric is always rejected, which is why
every cell below requires `recurring: true`.

| charge model | count_agg | sum_agg | max_agg | unique_count_agg | weighted_sum_agg | latest_agg | custom_agg | legal |
|---|---|---|---|---|---|---|---|---:|
| `standard` | · | ✓ | · | ✓ | · | · | ✓ | 3 |
| `graduated` | · | ✓ | · | ✓ | · | · | ✓ | 3 |
| `package` | · | · | · | · | · | · | · | 0 |
| `percentage` | · | · | · | · | · | · | · | 0 |
| `volume` | · | ✓ | · | ✓ | · | · | ✓ | 3 |
| `graduated_percentage` | · | · | · | · | · | · | · | 0 |
| `custom` | · | · | · | · | · | · | · | 0 |
| `dynamic` | · | · | · | · | · | · | · | 0 |
| **total** | | | | | | | | **9** |

**`prorated: true`, recurring metric, pay in advance** — `standard` only.

| charge model | count_agg | sum_agg | max_agg | unique_count_agg | weighted_sum_agg | latest_agg | custom_agg | legal |
|---|---|---|---|---|---|---|---|---:|
| `standard` | · | ✓ | · | ✓ | · | · | ✓ | 3 |
| all others | · | · | · | · | · | · | · | 0 |
| **total** | | | | | | | | **3** |

Note the three `custom_agg` cells in each prorated table: validation permits them, but prorated
aggregators exist only for `sum_agg` and `unique_count_agg`
(`BillableMetrics::AggregationFactory`). Rows covering them must set `characterization: true` —
they record what Lago does today rather than asserting intended behaviour.

**Fixed charges** — `FixedCharge` validation: `pay_in_advance` is invalid with `volume`, and
`prorated` is invalid with `graduated` + `pay_in_advance`. 9 of 12 combinations legal.

| charge model | advance + prorated | advance | arrears + prorated | arrears |
|---|---|---|---|---|
| `standard` | ✓ | ✓ | ✓ | ✓ |
| `graduated` | · | ✓ | ✓ | ✓ |
| `volume` | · | · | ✓ | ✓ |

### Action coverage

Cells cover data combinations; actions cover API operations. A suite can be at 100% cells and never
have called `PUT /invoices/:id/refresh`, so both are measured.

The action list is read from **Rails' own route table**, not by parsing `config/routes.rb`, so a new
endpoint cannot be missed by a regex. `actions.yml` says which controllers are in scope and which
individual actions are deliberately excluded; out-of-scope routes are counted and reported so the
boundary stays visible rather than silently shrinking the denominator.

| in scope | excluded by name | out of scope by controller | total mutating routes |
|---:|---:|---:|---:|
| 60 | 12 | 101 | 173 |

Excluded by name are PDF/XML downloads, email resends, metadata, and payment-provider flows
(`customers#checkout_url`, `wallet_transactions#payment_url`, `invoices#retry_payment`,
`invoices#lose_dispute`) — none of which are billing arithmetic.

### Reading RISK

| column | meaning |
|---|---|
| `ROWS` | rows declared for the block |
| `CELLS` | legal cells — the denominator |
| `COVER` | legal cells claimed by at least one row |
| `%` | `COVER / CELLS` |
| `FIXES` | `fix:`/`bug:` commits touching the block's services since 2024-01-01 |
| `RISK` | `FIXES × (uncovered / CELLS)` — expected unguarded bug density |

RISK is deliberately *not* fixes-per-uncovered-cell, which penalises large blocks: B1 has the
biggest absolute gap in the suite and would rank near the bottom. This form decays to zero as a
block approaches full coverage, so the ranking stays useful as the suite fills in.

RISK ranks *risk*, not *build order*. B15 needs the other blocks to exist first, and B14 is worth
doing early because it is nearly free.

---

## Row schema

Enforced by `schema.json`; unknown keys are rejected.

| field | type | required | meaning |
|---|---|:---:|---|
| `id` | string | ● | stable identifier, `b<NN>/<path>`. Must name its own block. Never reused for different behaviour |
| `block` | `B<N>` | ● | which block this row belongs to |
| `axes` | object | ● | the cell claimed. Must name **every** axis of the block — a partial claim is reported as malformed, not silently counted |
| `dimensions` | object | | pinned context that is *not* an axis. Documentation only; the ledger ignores it |
| `provenance` | string | ● | why the row exists: a ticket id, a commit sha, `coverage-gap`, `characterization`, `discover@<sha>` |
| `runners` | array | ● | `rspec`, `live`, or both |
| `premium` | bool | | tags the example `:premium`, enabling the licence |
| `characterization` | bool | | records current behaviour rather than asserting intended behaviour. Must be stated, never implied |
| `calendar_sensitive` | bool | | expectation depends on the absolute calendar (leap day, month length, `yday == 1`, DST) |
| `needs_forward_time` | bool | | needs the clock to move forward (trial end, deferred downgrade) |
| `no_transaction` | bool | | run with DatabaseCleaner's deletion strategy instead of a wrapping transaction |
| `custom_spec` | string | | escape hatch: a hand-written spec replacing the interpreted timeline |
| `setup` | object | ● | the world before the timeline runs |
| `timeline` | array | ◐ | ordered steps, each at an absolute instant. Exactly one of `timeline` or `at` |
| `at` | string | ◐ | ISO8601 instant for rows whose whole action *is* the setup (a resource-characterization row) |
| `expect` | object | ● | what must be true afterwards |
| `math` | string | ◐ | how the expected numbers are derived. **Mandatory when a non-zero amount is expected** |
| `note` | string | | free prose, for rows with no amounts |

### Setup

Materialised in this order, at the timestamp of the first timeline step: taxes → metrics → plan
(with charges inlined) → customer → coupons → wallets.

| key | shape | notes |
|---|---|---|
| `taxes` | `[{code, name, rate, applied_to_organization}]` | `applied_to_organization` defaults to true |
| `metrics` | `[{code, aggregation_type, field_name, recurring, weighted_interval, expression, rounding_function, rounding_precision, filters}]` | `field_name` required except `count_agg` / `custom_agg` |
| `plan` | `{code, name, interval, amount_cents, amount_currency, pay_in_advance, trial_period, bill_charges_monthly, tax_codes, minimum_commitment, usage_thresholds}` | defaults: monthly, 0 cents, EUR, arrears |
| `charges` | `[{billable_metric_code, code, charge_model, properties, pay_in_advance, prorated, invoiceable, regroup_paid_fees, min_amount_cents, tax_codes, filters}]` | referenced by metric **code**; the runner resolves the id |
| `customer` | `{external_id, name, currency, timezone, country, tax_codes, net_payment_term, invoice_grace_period, finalize_zero_amount_invoice}` | |
| `subscription` | `{external_id, billing_time, subscription_at, ending_at, on_termination_*, plan_overrides}` | consumed by the `create_subscription` step; `plan_overrides` creates a child plan (premium) |
| `coupons` | `[{...}]` | created then applied to the customer |
| `wallets` | `[{...}]` | created for the customer |

### Timeline

Each step is `{at: <ISO8601>, do: <verb>, ...}`. The RSpec runner wraps each step in `travel_to`;
the live runner shifts the whole timeline so the last step lands at "now".

| verb | extra keys | maps onto |
|---|---|---|
| `create_subscription` | `params` | `POST /subscriptions` |
| `ingest_events` | `events: [{code, properties, count, timestamp, precise_total_amount_cents}]` | `POST /events` per event |
| `pay_fees` | | `PUT /fees/:id` marking the subscription's uninvoiced charge fees succeeded |
| `pay_invoice` | `invoice_type` | `POST /payments` settling an invoice in full (premium + `manual_payments`) |
| `create_credit_note` | `credit_note: {reason, credit/refund/offset_amount_cents, items}` | `POST /credit_notes`; items name a `fee_type` and the runner resolves the fee id |
| `update_plan_charge` | `charge: {billable_metric_code, charge_model, properties, cascade_updates}` | `PUT /plans/:code/charges/:code` on the **parent** plan |
| `terminate_subscription` | `params` | `DELETE /subscriptions/:external_id` |
| `fetch_current_usage` | | `GET /customers/:id/current_usage`, and **snapshots** the result for `expect.usage` |
| `refresh_invoice` | | `PUT /invoices/:id/refresh` |
| `finalize_invoice` | | `PUT /invoices/:id/finalize` |
| `void_invoice` | | `POST /invoices/:id/void` |
| `perform_billing` | | `Clock::SubscriptionsBillerJob` + free-trial biller, then usage update |
| `perform_usage_update` | | daily usages, lifetime usages, subscription activities |
| `perform_invoices_refresh` | | `Clock::RefreshDraftInvoicesJob` |
| `perform_finalize_refresh` | | `Clock::FinalizeInvoicesJob` |
| `perform_wallet_refresh` | | `Clock::RefreshWalletsOngoingBalanceJob` |

The clock verbs are the façade `ScenariosHelper` already exposes, so rows use the vocabulary the
team already thinks in.

### Expectations

`expect` holds either `error` (terminal — a rejection, nothing else may be asserted) or some
combination of `invoices`, `invoice`, `usage` and `resource`.

**Rejections**

| field | required | meaning |
|---|:---:|---|
| `stage` | ● | which setup call must be rejected: `metric`, `plan`, `charge`, `customer`, `subscription`, `coupon`, `wallet` |
| `status` | ● | expected HTTP status |
| `code` | ● | Lago error code, e.g. `invalid_billable_metric_or_charge_model` |
| `field` | | `error_details` key, e.g. `prorated` |

Named `stage`, not `on`: YAML 1.1 parses a bare `on` key as boolean `true`.

**Invoice** — an allowlist. Volatile fields (`lago_id`, `number`, `sequential_id`, `created_at`,
`issuing_date`, `file_url`) are deliberately absent from the schema, so no row can pin one by
accident.

`expect.invoice` takes one expectation or a **list** of them. A list is how a row asserts money
moving *between* invoices — progressive billing crediting a period invoice, a coupon consumed by a
threshold invoice, a wallet top-up settling later. Each entry needs its own `select`; a lint rejects
duplicate or missing selectors, because two entries that resolve to the same invoice look like both
sides are covered while only one is. Failures name the selector (`invoice[invoice_type=subscription]`)
rather than just `invoice`.

| field | notes |
|---|---|
| `select` | which invoice: `first`, `last` (default), or `{index, invoice_type}`. Required on every entry of a list |
| `invoice_type` | `subscription`, `add_on`, `credit`, `one_off`, `advance_charges`, `progressive_billing` |
| `status` | `draft`, `finalized`, `voided`, `failed`, `pending`, `generating`, `open`, `closed`, `deleted` |
| `payment_status` | `pending`, `succeeded`, `failed` |
| `taxes_status` | `pending`, `succeeded`, `failed` |
| `currency`, `taxes_rate` | |
| `fees_amount_cents` · `coupons_amount_cents` · `credit_notes_amount_cents` | |
| `prepaid_credit_amount_cents` · `prepaid_granted_credit_amount_cents` · `prepaid_purchased_credit_amount_cents` | |
| `progressive_billing_credit_amount_cents` | |
| `sub_total_excluding_taxes_amount_cents` · `sub_total_including_taxes_amount_cents` | |
| `taxes_amount_cents` · `total_amount_cents` · `total_due_amount_cents` | |
| `fees_count` | asserted separately from `fees`, so "how many" fails distinctly from "which" |
| `fees` | array, see below |

**Fee fields** — flat names, mapped onto the payload by the runner.

| row field | payload path | notes |
|---|---|---|
| `fee_type` | `item.type` | `charge`, `subscription`, `add_on`, `credit`, `commitment`, `fixed_charge`, `product` |
| `item_code` | `item.code` | |
| `item_type` | `item.item_type` | |
| `units` · `precise_unit_amount` · `total_aggregated_units` | top level | compared numerically |
| `amount_cents` · `taxes_amount_cents` | top level | compared exactly |
| `taxes_rate` · `events_count` | top level | |
| `from_date` · `to_date` | top level | **not** `from_datetime` — see Known traps |

**Credit note** — asserted through `expect.credit_note`. Without `select` this means the note the
row's own `create_credit_note` step made. With `select` it reads the customer's credit notes, which is
the only way to assert one **Lago created by itself** — progressive billing issues one when billed
usage falls below what a threshold invoice already charged, and termination issues one on a cancelled
period. Neither passes through a step, so neither was assertable before.

| field | notes |
|---|---|
| `select` | `{index, credit_status, reason}`; absent means the step's own note |
| `credit_status` · `refund_status` · `reason` · `currency` | |
| `sub_total_excluding_taxes_amount_cents` · `taxes_amount_cents` · `taxes_rate` | |
| `credit_amount_cents` · `refund_amount_cents` · `offset_amount_cents` | tax-**inclusive** totals; `offset_amount_cents` is set only by termination notes |
| `total_amount_cents` · `balance_amount_cents` · `coupons_adjustment_amount_cents` | |
| `items_count` | |

**Usage**

| field | notes |
|---|---|
| `amount_cents` · `taxes_amount_cents` · `total_amount_cents` | |
| `charges_usage` | `[{billable_metric_code, charge_model, units, amount_cents}]`, matched by metric code |

Current usage describes the period **in progress**, so it must be captured while that period is still
open — after `perform_billing` the subscription has rolled into a fresh, empty one. A
`fetch_current_usage` step snapshots it for the assertion at the end; with no such step,
`expect.usage` reads live usage instead. A row can therefore assert usage *and* the invoice that
period later produces, which is how the usage-equals-invoice invariant is expressed.

**Resource** — for characterization rows where the API *accepts* the request but normalises the
input, so there is no error to assert and no invoice to inspect.

| field | notes |
|---|---|
| `kind` | `metric`, `plan`, `customer`, `charge` |
| `code` | which one, when the row declares several; defaults to the first |
| `fields` | attribute → expected value, read back through the resource's own GET endpoint |

### Comparison semantics

| kind | rule | why |
|---|---|---|
| `*_amount_cents` | exact | cents are the behaviour |
| `units`, `precise_unit_amount`, `total_aggregated_units`, `taxes_rate` | numeric (`BigDecimal`) | `"15.0"` vs `"15.00"` is a serializer detail |
| `from_date`, `to_date` | parsed, then compared | `Z` vs `+00:00` is not behaviour |
| fees | matched **by content, not position** | serializer ordering is an implementation detail |

Fee matching uses identity keys (`fee_type`, `item_code`, `item_type`, `from_date`, `to_date`) to
pick the fee, then asserts the remaining fields on it. That is deliberate: a wrong amount reports as
`fee #2: amount_cents expected 30001, got 30000` rather than the useless "no fee matched".

### Lints

Beyond the schema, `GoldenMatrix.lint_errors` enforces what JSON Schema cannot express:

| lint | rationale |
|---|---|
| unique `id` across all files | ids are the example names and the changelog keys |
| `id` prefix matches `block` | a row is locatable from a failure line alone (zero-padding optional: `b01` ↔ `B1`) |
| no non-String keys anywhere | YAML 1.1 turns `on`/`off`/`yes`/`no`/`y`/`n` into booleans; catches the whole class |
| `math` present when a non-zero amount is expected | a reviewer must be able to check the number without running anything |
| `calendar_sensitive` / `needs_forward_time` ⇒ not `live` | a row that cannot be shifted must not claim a runner that shifts |
| exactly one of `at` / `timeline` | a row either performs steps or is purely about what setup created |
| `expect.error` is terminal | a rejection short-circuits setup; asserting an invoice too is incoherent |
| every charge's metric is declared | catches a typo'd `billable_metric_code` at lint time, not mid-run |

---

## Results: what a run emits

`rspec spec/scenarios/golden` produces four integrity examples plus one example per row.

**The census**, printed every run, so a silently-empty matrix cannot read as a pass:

```
Golden matrix census (3 rows across 3 block(s)):
  B1   rows=1    cells=1    live=1    characterization=0
  B14  rows=1    cells=1    live=1    characterization=0
  B2   rows=1    cells=1    live=0    characterization=0
```

**The integrity examples:**

| example | fails when |
|---|---|
| is not empty | no matrix files, or no rows |
| validates every row against schema.json | any row violates the contract, naming file and id |
| passes the matrix lints | any lint above fires |
| reports the census | the per-block counts do not sum to the row count |

`legality_spec.rb` adds five more: four agreement checks against real `Charge` validation, and one
asserting every block axis resolves to a non-empty domain.

**The ledger** (`rake golden:ledger`) prints the coverage table, the action summary, the
highest-risk gaps, and a `DRIFT` section listing:

| drift kind | meaning |
|---|---|
| claims illegal cell | a row's axes name a combination Lago no longer permits — a validation rule moved |
| names axes `{missing:, extra:}` | a row's axes do not match its block's axes |

**Current rows** — three, one per block exercised so far, each chosen to prove a different part of
the harness:

| row | block | proves |
|---|---|---|
| `b01/volume/sum_agg/arrears/invoice` | B1 | a charge model with zero prior invoice coverage; that volume prices all units at the tier reached (15 × 20 = 30,000¢) where graduated would give 20,000¢ |
| `b02/monthly/anniversary/first-full-period/jan31-into-leap-february` | B2 | boundary assertions; Jan 31 anniversary clamps to Feb 28 23:59:59 in a leap year. `calendar_sensitive`, so rspec-only |
| `b14/prorated/non-recurring-metric/rejected` | B14 | the rejection path: HTTP status *and* exact error code *and* `error_details` key |

---

### The run report

`ruby dev/golden/report.rb` runs the suite, then answers three questions in order — and writes
nothing but `tmp/golden/`.

| section | contains | produces a proposal? |
|---|---|:---:|
| ① NOT PERFORMING AS EXPECTED | failures with **no commit** since the last green run touching the block's services | **no** |
| ② CHANGED | failures a commit **does** explain, with the commits named | yes |
| ③ NOT COVERED | new behaviour surface, ranked unclaimed cells, unclaimed actions | yes (rows to add) |

The ①/② split is decided by **evidence, not plausibility**: `blocks.yml` says which services a block
owns, and the script asks git for commits in `<last-green>..HEAD` touching them. No commit means ①,
however sensible the observed value looks. This is why the report runs on the host — `api` is a
submodule whose real `.git` is not mounted into the container.

The last-green marker lives in `tmp/golden/last_green.json` and is only advanced by
`--mark-green`, which **refuses while any example fails**. Until a green run is marked, the report
says so and leaves everything in ①.

Because the interpreter's failure messages are shaped `<field>: expected <a>, got <b>`, the report
recovers old → new mechanically and renders the proposal per field:

```
PROPOSED CHANGES — nothing written yet

  UPDATE 1 expectation
    b01/volume/sum_agg/arrears/invoice  (spec/scenarios/golden/matrix/b01_pricing.yml)
      total_amount_cents   31500 → 31000
      math: must be re-derived, not re-typed
      CHANGELOG.md += row id · old → new · 816d1292e · why

Apply?  [ all | updates only | additions only | none ]
`none` is always valid and leaves the suite red.
```

Applying is a separate, deliberate act. The script never edits a row.

Exit codes, so this can gate CI:

| code | meaning |
|---:|---|
| 0 | all green |
| 1 | suspected regressions present |
| 2 | only intended changes |
| 3 | could not run |

A real regression therefore **blocks the build** rather than silently self-healing. That is the
difference between a test suite and a dashboard.

### Discovering new behaviour

`surface.json` is a committed fingerprint of Lago's billing surface. `rake golden:discover`
recaptures it and reports the diff, which is what fills section ③ with things nobody thought to look
for.

| section | captured from | entries today |
|---|---|---:|
| `constants` | enumerating constants on 19 billing models | 59 |
| `routes` | Rails' route table, `api/v1` only | 254 |
| `clock_jobs` | `app/jobs/clock/*.rb` | 29 |
| `error_codes` | leaves under `activerecord.errors` in `en.yml` | 66 |
| `permitted_params` | `permit(...)` call sites per controller — approximate by design | 35 |
| `charge_model_defaults` | `ChargeModels::BuildDefaultPropertiesService` per charge model | 8 |

Everything is sorted, so a diff is a real change rather than a hash-ordering artefact. **Removals are
reported as loudly as additions**: a validation rule that stopped existing invalidates the rows that
assert it. `permitted_params` is scraped rather than invoked, because permitted params are not
introspectable — approximation is fine here, since a *change* in the set is the signal and a false
positive costs one look at a diff.

Record a new baseline with `rake golden:surface`, and only once the deltas have been turned into rows
or consciously dismissed — overwriting it early is how a discovery gets lost.

---

## The guardrail

**A failing row is a finding, not a chore.**

An `expect:` value may only change when you can name the commit or PR that intentionally changed the
behaviour. In the same edit: re-derive `math:`, append to `CHANGELOG.md` (row id, old → new, the
commit, one line of why), and say so in the report. Without that evidence the row stays red and is
reported as a suspected regression.

A self-maintaining suite that can rubber-stamp its own baselines is worth less than no suite at all.

---

## Known traps

Every one of these has already bitten this harness:

- **`/api/v1/invoices` (index) does not serialize fees.** Its includes are
  `%i[customer integration_customers metadata applied_taxes]`
  (`app/controllers/concerns/invoice_index.rb`). Fee assertions must read the invoice through
  `show`; asserting against the index silently compares to an empty array.
- **Fee period fields are `from_date` / `to_date`,** not `from_datetime`, and `fee_type` is nested at
  `item.type` (`V1::FeeSerializer`, `Fee#from_date`).
- **YAML 1.1 parses bare `on`, `off`, `yes`, `no`, `y`, `n` keys as booleans.** Hence `stage`, not
  `on`. A lint now rejects any non-String key anywhere in a row.
- **`ScenariosHelper#create_event` takes its payload positionally.** Passing keywords makes Ruby
  treat it as `**kwargs` and the method loses its only required argument.
- **Charges are inlined on plan creation,** so a charge-level rejection surfaces as a failure of
  `POST /plans`. B14 rows use `stage: charge`.
- **Validating only the charge is not enough** to decide whether a cell is reachable. `recurring:
  true` on a `count_agg` metric makes `Charge#validate_prorated` see a recurring metric, even though
  `BillableMetric#validate_recurring` forbids that metric from existing. Legality checks both.
- **The first period's `charges_from_datetime` is the subscription creation time,** not midnight —
  while the subscription fee's `from_datetime` is midnight. Boundary rows must expect both.
- **Four charge flags are silently dropped without a premium licence.** `Charges::CreateService`
  assigns `invoiceable`, `regroup_paid_fees`, `min_amount_cents` and `accepts_target_wallet` only
  inside `if License.premium?` (`app/services/charges/create_service.rb:46-53`). A non-premium caller
  sending `invoiceable: false` gets HTTP 200 and an *invoiceable* charge, with no error to tell it
  the intent was dropped. Rows testing those validations need `premium: true` or they pass for the
  wrong reason — the validation is never reached. B14 carries both the rejection rows (premium) and
  characterization rows recording the silent drop (non-premium).
- **Charge properties validators report on `properties`, not the specific key.** A bad
  `graduated_ranges`, `volume_ranges`, `package_size` or `per_transaction_max_amount` all surface as
  `error_details: {properties: [...]}` — even though the validator calls
  `add_error(field: :graduated_ranges)`.
- **`on_termination_credit_note` cannot be set on an arrears plan at all.** `Subscription` validates
  its *absence* when the plan is pay-in-arrears, so `none` is the only legal value on that side —
  which is why B9's axis lists `none` explicitly instead of deriving straight from
  `ON_TERMINATION_CREDIT_NOTES`, and why the block has 48 legal cells rather than 80.
- **A usage threshold is a trigger, not a cap.** Crossing a 2_000¢ threshold with 3_000¢ of accrued
  usage bills the full 3_000¢ mid-period, not 2_000¢ — billing only up to the threshold would leave
  the remainder uncollected until period end. The boundary is inclusive: landing exactly on the
  threshold fires it.
- **Progressive billing needs `no_transaction: true`.** The service runs inside an
  `idempotent_transaction`, which refuses to start while a wrapping transaction is open and fails as
  `An idempotent_transaction cannot be created in a transaction`. The row flag switches DatabaseCleaner
  to the deletion strategy, matching what `spec/scenarios/invoices/progressive_billing_spec.rb` does
  with `transaction: false`.
- **`PUT /plans/:code/charges/:code` is a full replacement, not a patch.** `charge_model` must be
  resent even when only `properties` change, or the request fails with
  `charge_model: [value_is_invalid, value_is_mandatory]`. A charge created inline on a plan takes its
  billable metric's code as its own, which is how a row identifies it.
- **Four premium flags are silently dropped, not rejected.** Beyond the three charge flags
  (`invoiceable`, `regroup_paid_fees`, `min_amount_cents`), `Customers::CreateService#assign_premium_attributes`
  returns early without a licence and drops `invoice_grace_period` and `timezone` too. The grace-period
  one changes invoice *state* rather than a flag: without it every invoice is finalized on creation, so
  late usage can never be picked up by a refresh. B14 carries characterization rows for all four.
- **`invoice_grace_period` and `document_locale` are nested under `billing_configuration`** in both
  request and response. Sent at the top level they are dropped by strong params — again with HTTP 200.
  A row asserting the top-level field would read `nil` whether or not the premium gate applied, and so
  would pass for the wrong reason; `expect.resource.fields` therefore supports dotted paths.
- **Event cardinality changes behaviour, so it is an axis.** Zero events still bills tier-1
  `flat_amount` (a graduated charge with no usage costs 10_000¢ in `b01/.../no-events`); one event
  cannot distinguish max_agg from sum_agg from latest_agg, nor cumulative-delta pricing from
  per-event pricing. B1 carries `events: none|one|many` and B3 `one|many`. Fixing the event set at
  three, as the first twelve B1 rows did, silently tests one third of each cell — and produced a
  confidently wrong entry in this very list.
- **Money that has not moved cannot move.** Three separate mechanisms enforce it, all failing
  quietly or with a late error rather than at the point of configuration: `regroup_paid_fees` only
  collects *succeeded* fees, purchased wallet credits are unusable until the top-up invoice is
  settled, and a refund credit note is rejected outright with
  `refund_amount_cents/cannot_refund_unpaid_invoice` unless the invoice was paid. Rows covering any
  of them need an explicit payment step.
- **Credit-note `items` are pre-tax; `credit`/`refund`/`offset` amounts are tax-inclusive.** With a
  20% tax, crediting a 3_000¢ fee whole means an item of 3_000¢ and a credit of 3_600¢. Passing 3_000
  as the credit under-credits by exactly the tax.
- **Credit notes are premium.** `POST /credit_notes` answers 403 `feature_unavailable` without a licence.
- **ScenariosHelper helpers take their payload positionally.** They are `(params, **kwargs)`, so
  bare keyword syntax is swallowed by kwargs and the call fails as
  `wrong number of arguments (given 0, expected 1)` — which does not point at the call site. This has
  now bitten `create_event`, `create_tax` and (latently) `apply_coupon`. Always brace the hash.
- **Purchased wallet credits are not spendable until the top-up invoice is paid.** A `paid_credits`
  top-up creates its wallet transaction `pending`, so a wallet that visibly holds 10 credits gives
  0¢ of cover on the next invoice. `POST /payments` settles it — and is itself premium, needing both
  `License.premium?` and the `manual_payments` premium integration, or it answers 403
  `feature_unavailable`. B6 carries both states as separate rows and separate axis values.
- **`regroup_paid_fees` means literally *paid* fees.** `Fees::CreatePayInAdvanceService` creates
  non-invoiceable fees `payment_status: pending`, while `Invoices::AdvanceChargesService` only
  collects fees that are `succeeded` and whose `succeeded_at` precedes the billing timestamp. Without
  a payment step no `advance_charges` invoice is produced at all and the usage is silently
  uninvoiced. That is what the `pay_fees` step verb exists for.
- **A pay-in-advance charge is priced as a cumulative DELTA, not per event.**
  `Charges::ApplyPayInAdvanceChargeModelService` computes
  `amount_from_aggregation − amount_excluding_persisted_event`, so tier flat fees, package boundaries
  and unique-count dedup all behave per PERIOD: a graduated charge bills its tier-1 flat fee once,
  not again on every event. (This entry previously claimed the opposite. The rows that "proved" it
  each ingested a single event, which cannot distinguish the two readings — see the events axis
  below.)
- **`custom_aggregator` is not a permitted REST parameter**
  (`Api::V1::BillableMetricsController#input_params`), so a `custom_agg` metric cannot be created
  through the API — a POST supplying one is still refused with `custom_aggregator/value_is_mandatory`
  because the parameter is filtered out before the service sees it. Those cells are excluded from the
  denominator via `GoldenLegality::API_UNREACHABLE_AGGREGATIONS`.
- **Git does not work inside the container.** `api` is a submodule whose real `.git` is not mounted,
  so anything git-derived is computed on the host and committed as data.
- **`annotate` rewrites `app/models/*.rb` on every test run,** and without
  `LAGO_DISABLE_SCHEMA_DUMP=true` the run also rewrites `db/structure.sql`.

---

## Two kinds of remaining work

What is left divides cleanly in two, and the division matters because the two halves have different
costs, different risks, and different people who can do them.

### Breadth — more rows

Adding rows is **incremental, safe, and parallelisable.** A block is roughly one sitting: pick the
highest-RISK uncovered block, write a spanning cross through its axes, derive each `math` line, run,
correct. Nothing already green can break, because rows are independent — the worst outcome is a row
that fails and teaches you something about Lago.

This is also where the suite pays for itself immediately: every block written so far surfaced at
least one real API behaviour that was not written down anywhere (see [Known traps](#known-traps)).
The work needs Lago domain knowledge and patience with arithmetic, not harness knowledge.

Rows do NOT need the skill, the live runner, or anything else on this list. If all structural work
stopped here, the suite would keep being useful and keep growing.

### Structure — the two things that change what the suite *is*

| item | turns the suite into | why it is different |
|---|---|---|
| `dev/golden/live_run.rb` | something that can check a **deployed** instance, not just a test DB | 68 of 70 rows already declare `runners: [rspec, live]` against a runner that does not exist. Until it does, that field is a promise, not a fact |
| `SKILL.md` in `lago-ai-skills` | something that **maintains itself** — audits coverage, discovers new behaviour, proposes rows, triages failures | The whole reason the matrix is data rather than code. Without it a human does the auditing forever |

These are one-off, they touch shared machinery, and getting them wrong has broader consequences than
a wrong row. They are also what was actually asked for: the rows are the *content*, the skill is the
*deliverable*.

### How to choose between them

Row work when you want coverage and findings now. Structural work when the marginal row is getting
cheaper than the marginal audit — which is roughly the point where writing a new block stops
teaching you anything about the harness. Nine blocks in, the harness has stopped changing shape
(the last four blocks needed step verbs but no new concepts), which is the signal that the
structural half is ready to be written down.

One asymmetry worth stating plainly: **row work compounds, structural work unblocks.** Fifty more
rows make the suite more useful linearly. The skill changes who can add the next fifty.

## Not built yet

Being explicit, so the gaps are visible rather than assumed:

- **The live HTTP runner** (`dev/golden/live_run.rb`). Rows already declare `runners:`,
  `calendar_sensitive` and `needs_forward_time` for it, but it does not exist. There is no HTTP
  time-travel endpoint in Lago, so it will shift each timeline so its last step lands at "now" and
  drive billing via `Clock::SubscriptionsBillerJob`. Rows that cannot shift stay rspec-only, and
  every skip will print its reason — a silently truncated run reading as full coverage is the
  failure mode most worth preventing.
- **Automatic application of a proposal.** The report renders `old → new` per field but never edits a
  row; applying is still a human or skill action, deliberately.
- **Actions.** Cell coverage is effectively done — 1,163 of 1,169 writeable cells (99%) across all
  21 blocks — but only 16 of 60 actions are exercised. See COVERAGE.md (a `rake golden:docs`
  build product, not committed) for the ranked gaps.
