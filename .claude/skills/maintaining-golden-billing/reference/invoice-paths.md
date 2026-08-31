# Which invoices exist, who raises them, and which can be a draft

Read this before writing any row that asserts `status: draft`, refreshes an invoice, or reasons about
a grace period. Getting it wrong is the most expensive mistake available here: a row asserting a draft
that was never a draft passes while testing nothing, and a row that *needs* a draft fails for a reason
that looks like the bug it was written to catch. BIL-537 took five attempts for exactly that.

**A grace period is not a property of the customer as far as an invoice is concerned. It is a property
of the service that raised the invoice.** `Invoices::SubscriptionService` consults `grace_period?`
(`subscription_service.rb:177,193`); other paths call `TransitionToFinalStatusService` directly and
finalize whatever the customer's setting says.

## The table

| invoice | raised when | draft under a grace period? | evidence |
|---|---|---|---|
| period invoice, arrears plan | period end | **yes** | many B18 rows |
| period invoice, advance plan | period start | **yes** | `b20/subscription-override/paid_advance_fee/draft` |
| subscription-start invoice, **advance** plan | subscription created | **yes** | same row — the plan being advance is what makes it a `subscription` invoice |
| subscription-start invoice, **arrears** plan whose only content is an advance fixed charge | subscription created | **NO — finalized on creation** | three probes: plan-units 10, plan-units 0 + creation override, and the following period invoice |
| advance-charge invoice (pay-in-advance charge, or a fixed-charge units delta) | on the event | **no** | the delta invoices in B13 and B20 |
| progressive-billing / threshold invoice | threshold crossed | not verified — assume no | B17 rows set the grace period *after* the threshold invoice deliberately |
| credit invoice (wallet top-up) | wallet purchase | not verified | B6 |

## Consequences that have already bitten

- **A plan paying in arrears cannot give you a draft at subscription start.** If a row needs an open
  invoice holding an advance fixed charge, the PLAN must be `pay_in_advance: true`. Three of the five
  BIL-537 attempts died here.
- **`plan_overrides` is indexed by UUID.** `Plans::OverrideService` and
  `Subscriptions::CreateService#create_fixed_charge_units_overrides` both key entries by the record's
  id, which a YAML row cannot know. The runner resolves it from `add_on_code`/`code`
  (`golden_plan_overrides`) — write the code, not an id.
- **A plan whose fixed charge has 0 units bills nothing at subscription start**, so the first invoice
  comes from the override path rather than the plan path. That is a different invoice, and only one of
  the two can be a draft.
- **A units-only subscription update does not clone the plan.** It writes a
  `Subscription::FixedChargeUnitsOverride` (`update_or_override_fixed_charge_service.rb:41-58`).
  Sending anything beyond `units`/`apply_units_immediately` switches to the plan-clone path, which
  rewrites charge ids — a different B20 churn entirely.

## What each surface does with the pipeline

| stage | finalized invoice | draft | refreshed draft | preview |
|---|---|---|---|---|
| fee producers (subscription, charge, fixed charge, commitment true-up) | ✓ | ✓ | ✓ | ✓ |
| progressive billing credit | ✓ | ✓ | ✓ | ✓ (invoice level only — no fee-level distribution) |
| coupon | ✓ | — | — | ✓ |
| tax | ✓ | ✓ | ✓ | ✓ |
| credit note | ✓ | — | — | ✓ |
| prepaid credit | ✓ | — | — | ✓ |

The three dashes are one line each in `calculate_fees_service.rb:364-379`:
`return false if not_in_finalizing_process?`. That gating is deliberate — it stops a draft from
consuming a `once` coupon or burning wallet credits that a refresh would have to give back.

**Progressive billing is the exception**, running at `:53`, ahead of the gate. So a draft shows the
credit but not the discount, and `b21/b12/draft` shows both sides of that line on one invoice: the
commitment true-up survives (a producer, above the gate) and the coupon does not.

## `POST /invoices/preview` has four contexts and names none of them

`Preview::SubscriptionsService#context` infers one from the params:

| params | context | what you get |
|---|---|---|
| no `subscriptions.external_ids` | `proposal` | a HYPOTHETICAL subscription — `add_charge_fees` returns early unless persisted, so **zero usage** |
| `subscriptions.external_ids` | `projection` | the existing subscription's next invoice — almost always what a row means |
| + `terminated_at` | `termination` | the final invoice |
| + nested `plan_code` | `plan_change` | the upgrade/downgrade invoice |

A row meaning "predict my next invoice" that gets a proposal asserts 0 and reads as a preview bug. The
harness defaults to projection; pass a top-level `plan_code` only when a proposal is genuinely wanted.

## Refresh and finalization are different

- `Invoices::RefreshDraftService` rebuilds a draft's fees from current configuration. It stays a draft,
  so the withheld reducers stay withheld.
- `RefreshDraftAndFinalizeService` calls the same service with `context: :finalize` **without
  consulting `ready_to_be_refreshed`**. So finalization always recomputes, and a writer that fails to
  flag drafts (`Charges::UpdateService`) delays a correction rather than losing it.
- `Clock::RefreshDraftInvoicesJob` only picks up flagged invoices. `PUT /invoices/:id/refresh` does
  not care about the flag. A row that means "the automatic refresh missed this" must use the clock job;
  one that means "recompute it now" must use the endpoint. They give different answers.
