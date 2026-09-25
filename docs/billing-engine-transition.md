# Separating billing context from financial execution

The target model separates four responsibilities:

| Model | Responsibility |
| --- | --- |
| `PricingSegment` | Effective pricing after resolving rates, phase overrides and their validity. |
| `BillingCycle` | One card's calendar period and the reference used for proration. |
| `BillingSegment` | A materialized part of a cycle with constant pricing and fixed quantity. |
| `BillingOperation` | Durable financial work, its outcome and the fees it produced. |

Pricing and billing segments describe context. Their existence will not imply that
another fee is owed. Fixed quantities describe contracted units; prior fees and
credits determine what remains financially covered.

## Step 1: persist calendar cycles

Newly produced billing segments reference a `BillingCycle`. Rate changes within
one period share that cycle, including when their segments become due in separate
producer runs. Cycles and segments are written atomically. The existing producer
schedule and consumer behavior remain in place during this step.

Cycle bounds are half-open. `started_at` is the first service instant of that
cycle, while `reference_started_at` is the preceding calendar boundary. They
differ for an initial stub. `ended_at` is the nominal next calendar boundary,
even when service terminates earlier. `timezone` preserves the convention used
to resolve those boundaries.

For a monthly card anchored on June 1, activated on June 15 and terminated on
June 21:

```text
BillingCycle.reference_started_at = June 1
BillingCycle.started_at           = June 15
BillingCycle.ended_at             = July 1
Service interval                 = [June 15, June 21)
Proration reference              = [June 1, July 1)
```

Identity is unique by card and cycle index, with a separate unique constraint on
card and start. Repeating a write reuses the cycle. A conflicting calendar returns
`calendar_conflict` and rolls back the batch rather than rewriting a prior
reference. Calendar corrections need an explicit policy in a later step.

Historical segments may have a null `billing_cycle_id`. Their existing fields and
readers remain available. This first step does not infer missing historical
boundaries from the latest pricing configuration.

## Following steps

1. Resolve and persist `PricingSegment` across cycles, including phase overrides.
   Give materialized `BillingSegment` rows their pricing reference and fixed
   quantity, splitting on quantity changes as well as pricing changes.
2. Move financial status, scheduling and retry identity to `BillingOperation`.
   Link financial results to operations and preserve their service coverage.
3. Materialize current context before billing is due, including arrears. Separate
   the context cursor from financial scheduling and use the same calculations for
   current usage and billing.
4. Backfill historical context in bounded batches, adapt all readers, then remove
   redundant segment fields. Progressive billing and alerts can build on the
   calculation and operation boundaries without making segments consumable again.

Each step must preserve the previous step's working billing path. Product choices
such as repricing advance coverage, tier resets and late-event corrections require
explicit rules and examples when those paths are implemented.
