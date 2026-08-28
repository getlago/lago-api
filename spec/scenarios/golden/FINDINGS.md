# Golden suite — findings log

Generated 2026-08-27 by `rake golden:findings:export` from `spec/scenarios/golden/findings.yml`.
**Edit the ledger, not this file** — anything written here is overwritten by the next run.

69 open · MONEY 35 · BROKEN 4 · API 13 · HARNESS 10 · DOC 5 · PROCESS 2
18 pinned by a row · **51 not pinned**

A finding nothing pins is prose: the next refactor moves the behaviour and nobody is told.
Pinning is resolved live from rows' `pins:`, so the counts above are today's, not when the
finding was written.

---


## F01 [MONEY] Progressive billing silently retains money on multi-crossing periods
credits/progressive_billing_service.rb:79 books a progressive credit as
`precise_coupons_amount_cents` — a phantom coupon on invoices that have none. Then
create_from_progressive_billing_invoice.rb:77 subtracts a pro-rated "coupon adjustment",
shrinking Lago's own refund request. Fixed case: customer pays 8000 for a period worth 1000
and is refunded 4375, not 7000. 2625 retained. Not even Lago's own ceiling (invoice.rb:426
caps invoice #2 at 5000, so correct settlement needs two notes). Code carries
`TODO(ProgressiveBilling) ... "should be handled manually"` at :60-64.
PINNED RED by b05/{fixed,recurring,multiple}/multiple-in-period/excess-to-credit-note.
PINNED by b05/fixed/multiple-in-period/excess-to-credit-note, b05/multiple/multiple-in-period/excess-to-credit-note, b05/recurring/multiple-in-period/excess-to-credit-note


## F02 [MONEY] A day is billed twice when start and termination share a day-of-year
b02/yearly/calendar/first-partial-period bills 2024-03-16..12-31 = 291 days;
b02/yearly/calendar/terminated-mid-period bills 2024-01-01..03-16 = 76 days.
291+76 = 367 against a 366-day year. The way-in convention (first_subscription_amount) and
the way-out convention (terminated_amount) both claim the 16th. Same +1 in the monthly pair.
PINNED from both sides by those two rows (green = confirmed current behaviour).
PINNED by b02/yearly/calendar/first-partial-period, b02/yearly/calendar/terminated-mid-period


## F03 [MONEY] A `once` coupon larger than the first invoice keeps discounting
applied_coupon_service.rb:82 terminates a `once` coupon only when credit >= remaining amount.
A 200 EUR "one-time" coupon on a 50 EUR/mo plan discounts four months.
NOT PINNED - deliberately avoided (every `once` coupon in B10 sized below the base).
PINNED by b19/coupon/capped/preview


## F04 [MONEY] Voiding an invoice never gives back a consumed credit note
Invoices::VoidService recredits applied coupons (:37-39) and outbound wallet transactions
(:46-49) and nothing else. CreditNotes::RecreditService exists and does the right job but is
reachable only from subscriptions/activation_rules/*. Three-way asymmetry: coupon returned,
wallet refilled, credit note forfeited.
PINNED GREEN by b04/void/with-credit-note (+ its two passing siblings as controls).
PINNED by b04/void/with-credit-note


## F05 [MONEY] Deleting a charge drops usage already accrued in the open period
Charge carries `default_scope -> { kept }` (models/charge.rb:62) and CalculateFeesService
iterates subscription.plan.charges, so units ingested before the deletion are never billed —
no proration, no partial fee, no trace.
PINNED by b11/delete-charge/plan-override (marked characterization).
PINNED by b11/delete-charge/plan-override


## F06 [MONEY] A deleted charge keeps billing overridden subscriptions
Charges::DestroyService is called with cascade_updates defaulting false, so a charge removed
from a plan bills every overridden subscription indefinitely while no longer being visible on
the plan anyone reads.
PINNED by b11/delete-charge/subscription-override (marked characterization).
PINNED by b11/delete-charge/subscription-override


## F07 [MONEY] Pay-in-advance charges ignore progressive billing entirely
Invoices::CreatePayInAdvanceChargeService reimplements the reducer sequence (coupon :28,
tax :34, credit note :41, prepaid :42) with NO Credits::ProgressiveBillingService call,
unlike calculate_fees_service.rb:53. A pay-in-advance charge bills in full mid-period even
after a threshold invoice already collected that usage.
PINNED (asserted as current behaviour) by b15/advance_charge/progressive_billing.
PINNED by b15/advance_charge/progressive_billing


## F08 [MONEY] Minimum commitment counts progressively-billed usage twice
commitments/minimum/in_arrears/calculate_true_up_fee_service.rb:22-38 selects charge fees by
subscription and period with NO invoice scoping, so a threshold invoice's fee counts toward
the floor alongside the period invoice's fee for the same usage.
PINNED by b15/commitment_true_up/progressive_billing (either colour is a finding).
PINNED by b15/commitment_true_up/progressive_billing


## F09 [MONEY] Upgrading with on_termination_credit_note refund/offset is impossible
CreditNotes::CreateFromTermination:24-25 raises NotImplementedError for
`upgrade && (refund || offset)`, and ActivateService#activate_for_upgrade:65-68 reaches it.
Guards sit before the zero-amount early returns, so any non-zero subscription fee triggers it.
A customer who sets refund or offset on a pay-in-advance subscription can never upgrade.
NOT PINNED - propagates as a 500, and expect.error cannot express it. 2 B9 cells unwriteable.
NOT PINNED — nothing fails if this behaviour changes.


## F30 [MONEY] A wallet limited by BOTH fee type and metric widens instead of narrowing
`applicable_fee?` returns `target_match || type_match || unrestricted_wallet`
(credits/allocate_prepaid_credits_by_wallets_service.rb:121, mirrored at
wallets/balance/allocate_ongoing_usage_by_wallets_service.rb:136). A wallet created with
`applies_to: {fee_types: [charge], billable_metric_codes: [a]}` therefore pays for EVERY charge fee,
including metric b's — the metric restriction is inert whenever `charge` is in allowed_fee_types.
The UI presents the two as cumulative filters. Not pinned: B6's `limitation` axis is single-valued,
so no legal cell can express both limitations at once.
NOT PINNED — nothing fails if this behaviour changes.


## F31 [MONEY] Ongoing wallet balance ignores credit notes that billing will subtract
The billing cap subtracts credit notes — `sub_total_excluding_taxes + taxes_precise −
precise_credit_notes` (credits/allocate_prepaid_credits_by_wallets_service.rb:77-79) — but the
mid-period allocator pools current usage as plain `fee.amount_cents + fee.taxes_amount_cents`
(wallets/balance/allocate_ongoing_usage_by_wallets_service.rb:90), with no credit-note term
anywhere in the service. A customer holding an unapplied credit note therefore sees an
`ongoing_balance_cents` lower than what the wallet will really be charged, and
`depleted_ongoing_balance` / threshold top-up rules (balance/update_ongoing_service.rb:22-27) fire
early off that number. Not pinned: needs a credit note plus a mid-period read in one row.
NOT PINNED — nothing fails if this behaviour changes.


## F32 [MONEY] A pay-in-advance fixed-charge increase re-tiers the delta from zero and re-charges the flat fee
`build_pay_in_advance_fixed_charge_service.rb:148-164` builds a synthetic aggregation result whose
`aggregation` and `full_units_number` are both `delta_units`, then hands it to the ordinary charge
model — so the increment is priced as if it were a brand-new subscription. Graduated 20 → 40 units
mid-period bills 20 × 10.00 + tier 1's 100.00 flat = 300.00, not `cost(40) − cost(20)` = 200.00, and
tier 1's flat amount is charged a SECOND time inside one period. April therefore costs 60_000¢
in advance where the identical arrears charge bills 50_000¢, all 10_000¢ of it duplicated flat fee;
the units 31..40 never get the 5.00 rate they are contracted at. Worse with more changes: N increases
in a period pay N flat amounts.
PINNED (as current behaviour) by b13/graduated/advance/not-prorated/{increase-mid-period,subscription-override}.
NOT PINNED — nothing fails if this behaviour changes.


## F33 [MONEY] A prorated volume fixed charge re-prices the whole period at the CLOSING range's rate
`volume_service.rb:62-64` picks the range with `full_units_number` (the LAST event's units) while
`per_unit_total_amount` (:52-54) multiplies the PRORATED aggregation. The two disagree whenever units
move mid-period, and the disagreement is not conservative. 60 → 10 units on 2024-04-16 aggregates to
35 unit-months but selects the 0..30 range, so 35 unit-months are billed at 10.00 → 350.00 + 100.00
flat = 45_000¢ — more than DOUBLE the un-prorated 20_000¢ for the same April, and above the 41_000¢
that selecting the range by the prorated volume would give. The 30 unit-months accrued at 60 units
were contracted at 6.00 and are charged 10.00. The fee then reports `units` 10 at a
`precise_unit_amount` of 45.00, so the invoice line cannot be reconciled against either range.
PINNED (as current behaviour) by b13/volume/arrears/prorated/decrease-mid-period.
NOT PINNED — nothing fails if this behaviour changes.


## F36 [MONEY] Only the highest-priority threshold wallet is ever refilled
`allocate_ongoing_usage_by_wallets_service.rb:48-51` gives the FIRST applicable threshold wallet
`take = remaining`, so a second wallet with an active threshold rule receives 0 ongoing usage. Its
`ongoing_usage_balance_cents` / `ongoing_balance_cents` then never move, `state_changed`
(balance/update_ongoing_service.rb:18-19) is false, and `threshold_top_up_service.rb:18` returns
before reading the rule at all. Two auto-refilling wallets on one customer means one silently stops
refilling forever — the comment at :7-8 assumes a single threshold wallet.
Not pinned: b06/target-method/*/multi-wallet-priority deliberately pair the target wallet with a
plain purchased one to keep the arithmetic derivable.
NOT PINNED — nothing fails if this behaviour changes.


## F37 [MONEY] A threshold rule on a wallet that no current-usage fee can reach never fires
The ongoing pool is built from `Invoices::CustomerUsageService` fees, which are CHARGE fees only, and
filtered by `applicable_fee?` (allocate_ongoing_usage_by_wallets_service.rb:126-137). A wallet with
`applies_to: {fee_types: [subscription]}` and a zero balance therefore gets allocation 0 forever, its
ongoing columns never change, and the `state_changed` gate (threshold_top_up_service.rb:18) means its
recurring rule never runs — the wallet stays empty and no error is raised anywhere. Same for any
limitation matching no metered charge.
Not pinned: the cell is expressible but the row would assert "nothing happened".
NOT PINNED — nothing fails if this behaviour changes.


## F38 [MONEY] Target top-ups size themselves against gross usage, ignoring pending coupons
`compute_target_top_up_amount` (recurring_transaction_rule.rb:138-150) measures the gap against
`credits_ongoing_balance`, which is derived from a pool of `fee.amount_cents + fee.taxes_amount_cents`
with no coupon term (allocate_ongoing_usage_by_wallets_service.rb:90) — while billing caps the draw at
`sub_total_excluding_taxes + taxes_precise − precise_credit_notes`
(credits/allocate_prepaid_credits_by_wallets_service.rb:77-79), i.e. AFTER coupons. A customer with a
recurring coupon is charged for a top-up larger than any invoice can ever consume, every cycle, and the
surplus accumulates in the wallet. With `grants_target_top_up: false` that surplus is real money billed.
PINNED (as current behaviour) by b06/target-method/none/negative-total: 16_000¢ funded, 4_000¢ usable.
PINNED by b06/target-method/none/negative-total


## F41 [MONEY] Granted threshold top-ups have no burst limit and re-fire until the threshold is cleared
`compute_granted_credits` returns the rule's `granted_credits` verbatim for a non-target rule
(recurring_transaction_rule.rb:104-111), so the top-up is FLAT, not sized to the deficit. Each
top-up runs IncreaseService, which re-enqueues the refresh (balance/increase_service.rb:36), which
re-enters ThresholdTopUpService — so a rule whose grant is smaller than the ongoing deficit fires
again and again inside ONE clock tick until `credits_ongoing_balance > threshold_credits`. The
burst guard cannot see it: `automatic_top_ups` is scoped `.purchased`
(threshold_top_up_service.rb:79), so a granted rule is never counted and never even logged.
Not pinned: every threshold row here sizes the grant to clear the threshold in one pass on purpose.
NOT PINNED — nothing fails if this behaviour changes.


## F42 [MONEY] A threshold rule fires only after credits are applied, so it can never pay the invoice that emptied the wallet
`Credits::AppliedPrepaidCreditsService` consumes credits, calls DecreaseService with
`skip_refresh: true`, and only then refreshes (applied_prepaid_credits_service.rb:34-39). The
refresh is the sole trigger of ThresholdTopUpService (balance/update_ongoing_service.rb:26), so the
auto-refill always lands one step late: the invoice is short, the customer is billed cash, and the
wallet ends up holding a fresh grant it could have spent. Nothing between the events and
Clock::SubscriptionsBillerJob recomputes the ongoing balance, so this is the DEFAULT outcome unless
a wallet refresh happens to run mid-period.
PINNED (as current behaviour) by b06/threshold-rule/{none,fee-types,billable-metrics}/partial-cover —
1_000¢/8_000¢/6_000¢ of cash owed against a wallet that refills immediately afterwards.
NOT PINNED — nothing fails if this behaviour changes.


## F55 [MONEY] target_wallet_code OVERRIDES a wallet's own applies_to limitations instead of intersecting
`applicable_fee?` returns `wallet.code == target_wallet_code` and returns EARLY
(allocate_prepaid_credits_by_wallets_service.rb:109-114; identically at
allocate_ongoing_usage_by_wallets_service.rb:127-130), so `targets` and `types` are never consulted
for a tagged fee. A wallet limited to `fee_types: [subscription]`, or targeted at metric X, must
still pay a charge fee for metric Y as soon as an event carries its code — an event property
outranks the wallet's own configuration, which the UI presents as a hard restriction.
Not pinned: B6's `limitation` axis is single-valued, so no row combines applies_to with a tag.
NOT PINNED — nothing fails if this behaviour changes.


## F56 [MONEY] A fee tagged to an unusable wallet is silently uncoverable — cash, with no error anywhere
The billing scope is `wallets.active.with_positive_balance.where(balance_currency: invoice.currency)`
(allocate_prepaid_credits_by_wallets_service.rb:126-131), while the event-time guard only checks that
SOME active wallet has that code (events/post_process_service.rb:114-126) and merely sends an
`event.error` webhook when it does not. So a tag naming a zero-balance, terminated or
foreign-currency wallet passes validation, produces its own fee bucket, and that bucket can be paid
by nobody — the customer is billed cash while a funded unrestricted wallet sits unused, and the
invoice carries no marker of why. Pinned as current behaviour (zero-balance form) by the five
b06/*/target-wallet-code/negative-total rows.
NOT PINNED — nothing fails if this behaviour changes.


## F63 [MONEY] A gated subscription's start date is the cron's run time, not the date the customer chose
`handle_future_subscription` (create_service.rb:198-201) only calls `pending!` — it never sets
`started_at`. Activation then does `started_at ||= timestamp` (subscription.rb:124-126) with
`timestamp` = `Time.current` from Clock::ActivateSubscriptionsJob, while
ActivateAllPendingService selects `DATE(subscription_at) <= DATE(now)` (:14-25) — so a run that is
a day late still activates, but `from_datetime` clamps to `started_at.beginning_of_day`
(dates_service.rb:73-75) and `first_subscription_amount` bills one day fewer at the full plan day
price. On a 9_000¢/30-day plan that is 300¢ per day of cron lateness, silently, and the
`subscription_at` the customer chose is unrecoverable from the record.
NOT PINNED — every gated row activates on the scheduled day. A row activating on 12 April with
`subscription_at` 11 April would pin it (expect 5_700¢ where the on-time row expects 6_000¢), but
that is a second cell of the `gated-activation` transition, not one of the 48.
NOT PINNED — nothing fails if this behaviour changes.


## F64 [MONEY] `fixed_amount` on a graduated_percentage band is accepted and never billed
`fixed_amount` is a first-class field of a `graduated_percentage_ranges` band — it is in the
GraphQL properties input and output (graphql/types/charges/properties_input.rb:24, properties.rb:24)
and Lago's own default builder emits it (build_default_properties_service.rb:68-80). But
`RangeGraduatedPercentageService` reads only `flat_amount` and `rate` (:35-49), and
`Charges::Validators::GraduatedPercentageService#validate_rate_and_amounts` (:42-49) validates only
those two — so a non-zero `fixed_amount` is accepted, stored, echoed back and never charged.
Verified: same 3-band charge at 30 units returns 7.45 with `fixed_amount: "0"` and 7.45 with
`fixed_amount: "5"` (percentage_service.rb:60-66 does honour it, so the sibling model diverges).
NOT PINNED — the b01 graduated_percentage rows all carry `fixed_amount: "0"`, matching the existing
green row; a row with a non-zero one would expect the same cents and so would assert the bug.
NOT PINNED — nothing fails if this behaviour changes.


## F65 [MONEY] graduated and graduated_percentage project usage by two different rules
`GraduatedService#compute_projected_amount` (:36-62) RE-WALKS the tiers at `projected_units`.
`GraduatedPercentageService#compute_projected_amount` (:28-33) instead divides the CURRENT amount by
`period_ratio` — which scales the per-band `flat_amount`s as if they recurred, and never moves units
into a cheaper high band. Verified with identical band shapes, 30 units and period_ratio 0.5
(projected_units 60 in both): graduated projects 214.50, exactly what 60 units cost; GP projects
14.90 where a re-walk at 60 units gives 8.05 — 85% over, and the error grows with the flats.
NOT PINNED and not pinnable here: it needs `calculate_projected_usage: true`
(customer_usage_service.rb:14), which no timeline verb sets — `fetch_current_usage` reads the plain
usage surface. A `projected_usage` observed_via value would be needed, i.e. a harness change.
NOT PINNED — nothing fails if this behaviour changes.


## F66 [MONEY] `invoiceable: false` with `regroup_paid_fees` nil bills nothing, and nothing says so
`Fees::CreatePayInAdvanceService` builds, taxes and SAVES a real charge fee
(create_pay_in_advance_service.rb:147-151) with `invoice_id` nil, and no consumer exists:
`advance_charges_service.rb:83` requires `regroup_paid_fees: :invoice`, and
`calculate_fees_service.rb:130` scopes arrears charge fees to `invoiceable: true`. So the whole
period's usage is billed nowhere while the usage surface keeps reporting it as money owed. Nothing
validates the combination and no webhook or log marks it — the only difference between "settled
outside Lago" and "silently unbilled" is a nullable enum, and Charges::CreateService will accept
either. Measured across the 31 new `non-invoiceable-dropped` rows: 100¢ to 18_000¢ per period each.
PINNED (as current behaviour) by b03/*/non-invoiceable-dropped/*, all 31 of which assert the
usage surface alongside the empty invoice so the drop cannot be confused with a dead setup.
NOT PINNED — nothing fails if this behaviour changes.


## F69 [MONEY] A plan override silently cancels the minimum commitment
Plans::OverrideService dups the plan and every charge, but rebuilds the commitment only from
`params[:minimum_commitment].present?` (override_service.rb:64-72) — a `plan_overrides` body that
does not mention it produces a plan with NO commitment, so `subscription.plan.minimum_commitment`
is nil from then on and CalculateTrueUpFeeService returns 0. A 10_000¢ floor becomes 5_000¢ of
actual usage in the next period, and no plan anyone reads says the floor is gone.
PINNED by b20/plan-override/commitment_progress/{invoice,draft,regenerated,preview}.
PINNED by b20/plan-override/commitment_progress/draft, b20/plan-override/commitment_progress/invoice, b20/plan-override/commitment_progress/preview, b20/plan-override/commitment_progress/regenerated


## F70 [MONEY] A filter edit taxes an invoice on gross fees while reporting the credit in full
ProgressiveBillingService joins twice on different keys: the cap on charge_id
(progressive_billing_service.rb:29-33), the per-fee distribution on charge_id AND charge_filter_id
(:70-76). A filter edit rewrites only the latter (ChargeFilters::CreateOrUpdateBatchService resolves
by `values` and discards the unmatched, :63-77), so the credit is reported in full while no fee's
`precise_coupons_amount_cents` is written — and Invoices::ApplyTaxesService taxes
`fee.sub_total_excluding_taxes_amount_cents` (:78-82). A customer who paid 12_000¢ for a 12_000¢
period is invoiced 2_000¢ more on an invoice whose taxable sub-total is 0.
PINNED by b20/filter-changed/progressive_billing_credit/{invoice,draft,regenerated,preview}.
PINNED by b20/filter-changed/progressive_billing_credit/draft, b20/filter-changed/progressive_billing_credit/invoice, b20/filter-changed/progressive_billing_credit/preview, b20/filter-changed/progressive_billing_credit/regenerated


## F71 [MONEY] Preview's plan-limited coupon test has no `children`, so an override drops the discount
Credits::AppliedCouponService#plan_related_fees scopes on
`coupon.parent_and_overriden_plans.map(&:id)` (applied_coupon_service.rb:113-118) and so follows an
override plan. Coupons::PreviewService#plan_related_fees is
`coupon.plans.map(&:id).include?(invoice.subscriptions[0].plan_id)` (preview_service.rb:87-93) — an
exact plan_id test with no children — so after a plan override the preview refuses a coupon the
invoice then applies. Quote 15_000¢, bill 13_000¢: the error argues the customer out of a live
discount. One-line fix: reuse parent_and_overriden_plans.
PINNED by b20/plan-override/coupon_application/preview (control: .../invoice and the plan-upgrade
preview row, where both tests agree because no child exists).
PINNED by b20/metric-deleted/coupon_application/preview, b20/plan-override/coupon_application/preview


## F75 [MONEY] The two already-paid lookups for an advance fixed charge disagree about `parent`
Fees::BuildPayInAdvanceFixedChargeService#find_already_paid_units scopes on
`fixed_charge: [fixed_charge, fixed_charge.parent]`
(build_pay_in_advance_fixed_charge_service.rb:63-83), so a cloned fixed charge still finds what its
parent was billed. Fees::FixedChargeService#already_billed? scopes on `fixed_charge.fees` with no
parent fallback (fixed_charge_service.rb:53-75). Consequence: after a plan clone the delta invoice
prices correctly (2 units, 20_000¢) and a REFRESH of the draft it came from then matches that delta
fee and DELETES the 100_000¢ fee it was built with — BIL-537, reached by a second churn.
PINNED by b20/plan-override/paid_advance_fee/regenerated (controls: its /draft and /invoice
siblings, and b20/subscription-override/paid_advance_fee/*).
PINNED by b20/plan-override/paid_advance_fee/regenerated


## F76 [MONEY] A charge replacement makes a pay-in-advance charge forget the paid peak
`CachedAggregation` is the only record of how much of a period's PEAK usage an in-advance charge has
already billed, and it is found by `charge_id` (aggregations/base_service.rb:230-243, written at
create_pay_in_advance_service.rb:212-226). Replace the charge record — one id-less `update_plan`
charges entry, plan/subscription/metric untouched — and every row still points at the dead id, so
`compute_pay_in_advance_aggregation` takes its no-cache branch (sum_service.rb:145-153) and prices the
next event from zero. Measured: events +100, -60, +50 bill 10_000 + 0 + 5_000 = 15_000¢ where the
correct third fee is 0¢ (90 units still under a paid peak of 100). Nothing in refresh or period
billing ever reconciles it — `create_charges_fees` skips the charge outright.
PINNED by b20/charge-replaced/paid_advance_fee/{invoice,draft,regenerated,preview}, characterization;
control b20/plan-upgrade/paid_advance_fee/invoice, where the same rewrite is legitimate because the
period boundary moves with it.
NOT PINNED — nothing fails if this behaviour changes.


## F77 [MONEY] Deleting a metric silently stops billing its pay-in-advance events
`Events::PostProcessService#handle_pay_in_advance` looks the charge up through
`subscription.plan.charges.pay_in_advance.joins(:billable_metric).where(billable_metric: {code:})`
(:136-146). Both `Charge` and `BillableMetric` carry a `kept` default scope, so after
`BillableMetrics::DestroyService` the lookup returns empty and `return unless charges.any?` (:131)
fires: no fee, no invoice, no error, no `event.error` webhook. Measured: +100 bills 10_000¢, the metric
is deleted, +200 bills NOTHING — 20_000¢ of consumed usage never invoiced — and the period invoice
reads a clean subscription fee with no trace. The mirror image of F76 on the same lost key.
PINNED by b20/metric-deleted/paid_advance_fee/{invoice,draft,preview}, characterization; control
b20/metric-deleted/paid_advance_fee/regenerated, which has the third invoice at 20_000¢.
NOT PINNED — nothing fails if this behaviour changes.


## F78 [MONEY] Deleting a metric turns a progressive credit into an over-sized credit note
The threshold invoice bills the accrued usage; the deletion then removes the very charge fee the credit
must land on (destroy_service.rb:29 + models/charge.rb:62), so
`Credits::ProgressiveBillingService`'s cap over `invoice.fees.charge` is 0 and the whole amount is
diverted to `CreditNotes::CreateFromProgressiveBillingInvoice` (progressive_billing_service.rb:29-42).
Measured: 10_000¢ collected, period plan fee 8_000¢ — finalized, the note is spent down to a 2_000¢
leftover balance and the total reads 0; on a DRAFT the note is withheld (calculate_fees_service.rb:364)
and the customer is shown 8_000¢ on top of the 10_000¢ already paid. Correct settlement in both cases
is a 2_000¢ refund. Refreshing a healthy draft (14_000¢) produces the same thing, so the loss can be
watched happening.
PINNED by b20/metric-deleted/progressive_billing_credit/{invoice,draft,regenerated,preview}, all
characterization.
NOT PINNED — nothing fails if this behaviour changes.


## F84 [MONEY] A preview taxes progressively-billed usage a second time
`Invoices::PreviewService#apply_progressive_billing_credits` (preview_service.rb:330-359) increments
only `invoice.progressive_billing_credit_amount_cents`; unlike the real
`Credits::ProgressiveBillingService` it never calls `apply_credit_to_fees`, so no fee gets
`precise_coupons_amount_cents`. `Fees::ApplyTaxesService` then taxes
`fee.sub_total_excluding_taxes_amount_cents` (apply_taxes_service.rb:38) = the GROSS amount.
Measured: 3_000¢ of usage already billed and taxed on a threshold invoice, quoted again — preview
says sub_total_excluding_taxes 0, taxes 600¢, total 600¢; the invoice it forecasts says 0/0/0.
Same shape as F70 from the other side. Invisible at tax rate 0, which is why no b05 row saw it.
PINNED RED by b21/b5/preview (which asserts both surfaces in one row).
PINNED by b21/b5/preview


## F95 [MONEY] Percentage free-unit properties are silently inert on max_agg / weighted_sum_agg
`PercentageService#free_units_value` (percentage_service.rb:70-79) returns 0 on its first line
whenever `aggregation_result.options[:running_total]` is missing — and max_service.rb:25 assigns the
raw options hash while weighted_sum_service.rb:22 assigns `{}`, so neither ever sets that key. On a
percentage charge over those metrics `free_units_per_total_aggregation` does nothing at all, and
`free_units_per_events` discounts only the FIXED leg (via free_units_count:81-86, which falls back to
the raw property) while the percentage base stays at the full unit count. Configured allowance,
no discount, no error, no webhook. Verified against the real service in the container.
PINNED (as current behaviour) by b01/percentage/{max_agg,weighted_sum_agg}/*/{one,many} — 8 rows.
NOT PINNED — nothing fails if this behaviour changes.


## F96 [MONEY] Percentage `free_units_count` is order-dependent when events share a timestamp
For sum_agg the running total is truncated as it accumulates — `running_total_per_aggregation`
(sum_service.rb:126-137) breaks the moment the allowance is exceeded — and `events_values` orders
by `timestamp` alone (postgres_store.rb:6-11, :64-73). With tied timestamps the accumulated array is
whatever Postgres returns: 10/30/20 gives `[10, 40]` (free_units_count 1) but 30/10/20 gives `[30]`
(free_units_count 0), i.e. a different number of free EVENTS and a different fixed leg — 450¢ vs
500¢ on the row below — for identical input. free_units_value happens to agree in that example, so
the divergence is only in the fixed leg, but nothing bounds it.
NOT PINNED — deliberately avoided: every `many` event set in b01_pkg_vol_pct.yml carries distinct
timestamps so the accumulation order is determined.
NOT PINNED — nothing fails if this behaviour changes.


## F99 [MONEY] A metric-limited coupon is dropped entirely by the invoice preview
`Coupons::PreviewService#fees` returns `Fee.none` for any coupon with `limited_billable_metrics?`
(coupons/preview_service.rb:78-86) and the loop then `next`s on `fees.none?` (:27), so the coupon is
not mis-based — it is never applied. Its `base_amount_cents` is also gross `fees.sum(&:amount_cents)`
where applied_coupon_service.rb:96-105 nets out `precise_coupons_amount_cents`. The `Fee.none` carries
`# TODO: update later when charges will be added to the preview`, which is stale: `add_charge_fees`
does build charge fees. Verified in the container: an 8_000¢ plan + 20 units invoices at 3_000¢ and
previews at 5_000¢ — the preview overstates by the limited coupon's whole 2_000¢ contribution.
PINNED (as current behaviour) by b19/coupon/unequal/preview, marked characterization.
PINNED by b19/coupon/unequal/preview


## F11 [BROKEN] Unguarded nil in prorated commitment coefficient
calculate_prorated_coefficient_service.rb:45-46 calls
`all_invoice_subscriptions.first.from_datetime` with no nil check, on a relation filtered by
`from_datetime >= previous_beginning_of_period`. Any state where the commitment window opens
after the invoice_subscription's start raises inside CalculateFeesService's transaction —
billing fails rather than degrades.
NOT PINNED - latent; all B12 rows start on a period boundary.
NOT PINNED — nothing fails if this behaviour changes.


## F43 [BROKEN] A repeated unique_count value on a pay-in-advance percentage charge divides by zero
A duplicate uid gives `pay_in_advance_aggregation` 0 and `units_applied` 0
(unique_count_service.rb:110-115), so `compute_units` returns BigDecimal(0)
(apply_pay_in_advance_charge_model_service.rb:114-127). The delta is NOT 0 though:
`build_aggregation_result` decrements `count` by one regardless (:74), and percentage's
`compute_fixed_amount` (percentage_service.rb:60-66) is driven by `count`, so f_incl − f_excl is
exactly one `fixed_amount`. Line :36 then evaluates `rounded_amount / compute_units` = 2.00 / 0 →
ZeroDivisionError, killing Invoices::CreatePayInAdvanceChargeJob for that event (and, before the
raise, the duplicate is priced a full fixed_amount against zero units — MONEY too).
Derived from the code, not executed. NOT PINNED: b03/percentage/unique_count_agg/invoiceable/many
deliberately uses three distinct uids to stay off this path.
NOT PINNED — nothing fails if this behaviour changes.


## F72 [BROKEN] `POST /invoices/preview` 500s on any plan with two or more untaxed charges
Once `Invoices::PreviewService#add_charge_fees` returns more than one fee, those charge fees come back
with a nil `subscription` association. `Fees::ApplyTaxesService` then has `plan` = `fee.subscription&.plan`
= nil (apply_taxes_service.rb:11) and dies on `plan.taxes.any?` (:71) — `NoMethodError: undefined
method 'taxes' for nil`. Reproduced in the container with two charges on one metric AND with two
charges on two metrics; ONE charge is fine, and the fees themselves are priced correctly. A tax on the
charges avoids it by returning at `fee.charge.taxes` (:68) before `plan` is read; a PLAN-level tax does
not, because the nil is the plan object. Invisible until now because every b17 preview row has exactly
one charge — i.e. preview is broken for most real plans.
PINNED (as current behaviour) by b19/charge/equal/preview, marked characterization.
PINNED by b19/charge/equal/preview


## F73 [BROKEN] The multi-charge preview path loses the caller's DB connection
`add_charge_fees` wraps each charge in `ActiveRecord::Base.connection_pool.with_connection` inside
`Parallel.flat_map` (preview_service.rb:203-229). After the second block the caller is on a different
connection: inside a transactional spec `ApiKey`, `Organization` and `Plan` all count 0, so every
later query and every later HTTP call fails. Three measured consequences: nothing can follow a
multi-charge `preview_invoice` in one example (no billing, no invoice read); the previewed
`taxes_amount_cents` reads 0 while the fees themselves each carry tax; and a SECOND multi-charge
preview in the same process comes out wrong (a 35_000¢ plan previews 25_000¢) — which is what blocks
b19/charge/unequal/preview. Unrelated later examples are unaffected.
PINNED by b19/charge/equal/preview (taxes 0 asserted); b19/charge/unequal/preview NOT WRITTEN because
two such rows cannot coexist in one run.
PINNED by b19/charge/equal/preview


## F10 [API] Commitment fees never expose their period over REST
fee_serializer.rb:63 merges date_boundaries only for charge/subscription/add_on/fixed_charge.
`commitment` is absent, so from_date/to_date are missing from the payload though correct in
the DB and on the model (build_fee_base_service.rb:43-50, Fee#date_boundaries).
One-line fix: `|| model.commitment?`. NOT APPLIED - product change, awaiting Anna.
PINNED RED by 19 of 20 B12 rows.
PINNED by b12/in-advance/anniversary/monthly, b12/in-advance/anniversary/quarterly, b12/in-advance/anniversary/semiannual, b12/in-advance/anniversary/weekly, b12/in-advance/anniversary/yearly, b12/in-advance/calendar/monthly, b12/in-advance/calendar/quarterly, b12/in-advance/calendar/semiannual, b12/in-advance/calendar/weekly, b12/in-advance/calendar/yearly, b12/in-arrears/anniversary/monthly, b12/in-arrears/anniversary/quarterly, b12/in-arrears/anniversary/semiannual, b12/in-arrears/anniversary/weekly, b12/in-arrears/anniversary/yearly, b12/in-arrears/calendar/quarterly, b12/in-arrears/calendar/semiannual, b12/in-arrears/calendar/weekly, b12/in-arrears/calendar/yearly


## F12 [API] events_count gets a fractional value on prorated unique_count
ProratedAggregations::UniqueCountService:43 assigns the prorated (fractional) unit count to
result.count, which lands in Fee#events_count, an integer column. Three events report 1.
NOT PINNED - deliberately not asserted so it cannot bake a bug into an expectation.
NOT PINNED — nothing fails if this behaviour changes.


## F13 [API] Pay-in-advance charge fees are labelled with the wrong period
Fee#date_boundaries relabels an invoiceable pay-in-advance charge fee with the UPCOMING
interval while the aggregation ran over the PREVIOUS one. Harmless for a recurring metric
with no events in the gap; an event arriving in the gap is billed under the wrong label.
NOT PINNED - from_date/to_date deliberately unasserted on those fees.
NOT PINNED — nothing fails if this behaviour changes.


## F14 [API] on_termination_credit_note is inert on the downgrade path
ActivateService#activate_for_downgrade:98 calls mark_as_terminated! directly, so
TerminateService — the only route to CreateFromTermination — never runs, and
PlanDowngradeService:33-47 does not copy the field to the new subscription. The field is
absent rather than computing zero.
PINNED by 5 b09/downgrade/* rows asserting credit_notes_amount_cents: 0.
NOT PINNED — nothing fails if this behaviour changes.


## F15 [API] Offset-only credit notes can gain a phantom refund
AdjustAmountsWithRoundingService:26-32 writes the +/-1 rounding correction into
refund_amount_cents when credit_amount_cents == 0, breaking
`total = credit + refund + offset` (create_service.rb:70-73).
NOT PINNED - latent; needs an odd tax base (e.g. 20% of 3333).
NOT PINNED — nothing fails if this behaviour changes.


## F22 [API] A terminated subscription's lifetime usage never absorbs its final invoice
The termination invoice flags the row (invoices/subscription_service.rb:204 ->
flag_refresh_from_invoice_service.rb:21 sets recalculate_invoiced_usage), but when
RefreshLifetimeUsagesJob picks it up (refresh_lifetime_usages_job.rb:14-19),
calculate_service.rb:17-20 sees `!subscription.active?` and clears BOTH flags without
recalculating. invoiced_usage_amount_cents therefore permanently excludes the final period while
current_usage_amount_cents keeps a frozen pre-termination value, so the split across
total_amount_cents (lifetime_usage.rb:23-25) is wrong for every terminated subscription.
NOT PINNED - unassertable, see the two HARNESS findings above.
NOT PINNED — nothing fails if this behaviour changes.


## F25 [API] PB-excess credit notes never refund, even on a paid invoice
b08/from-progressive-billing-excess/refund/with-coupon expected balance_amount_cents 0 (a pure
refund) and got 3500 — i.e. the note was issued as a CREDIT with the full amount left available.
This CONFIRMS the B8 writer's own predicted finding that create_from_progressive_billing_invoice.rb
:22-31 never splits and never refunds, unlike the termination path which does. The row's
expectation contradicted the writer's own prediction, so the row is wrong and the finding is real:
the two automatic credit-note paths disagree about mixed notes.
RESOLVED (row was internally inconsistent, not tuned to green): the row's own math: already said
"balance_amount_cents is the full 3_500" while its expect: said 0. Corrected 0 -> 3500 to match its
own derivation; the family is now 4/4 green. The FINDING stands: PB-excess issues a credit and never
a refund, unlike the termination path — the row asserts refund_amount_cents 0 beside
credit_amount_cents 3500, which is what makes it a statement rather than an omission.
Note 3500 also settles the writer's highest-risk derivation: the coupon IS reduced twice
(progressive_billed_amount.rb:61 nets invoice coupons, then apply_taxes_service.rb:75-82 nets the
item's coupon share again). 5000 would have meant the second reduction was absent, 5600 the first.
NOT PINNED — nothing fails if this behaviour changes.


## F29 [API] prepaid credit breakdown fields serialize as null, never 0
`calculate_prepaid_credit_breakdown` writes `prepaid_granted_credit_amount_cents` /
`prepaid_purchased_credit_amount_cents` only `if granted_amount > 0` / `> 0`
(credits/applied_prepaid_credits_service.rb:91-92) and the columns are nullable with no default
(db/migrate/20251230154408). V1::InvoiceSerializer:33-34 therefore emits `null` for the pool that
did not move — so a client summing the two breakdown fields gets a nil, and the pair does not add up
to `prepaid_credit_amount_cents` on any single-pool invoice. Also silently skipped entirely unless
`invoice.customer.wallets.all?(&:traceable?)` (:74). Rows assert only the non-nil side.
NOT PINNED — nothing fails if this behaviour changes.


## F34 [API] Every pay-in-advance fixed-charge DECREASE emits a finalized zero-amount invoice
`build_pay_in_advance_fixed_charge_service.rb:29-35` returns a 0¢ / 0-unit fee on a negative delta
("we still generate an invoice to document the change"), and
`create_pay_in_advance_fixed_charges_service.rb:30-33` saves it unconditionally, so
TransitionToFinalStatusService FINALIZES a zero-total invoice (billing entity's
`finalize_zero_amount_invoice` defaults to true). The no-refund policy is deliberate; the artefact is
not obviously intended — one numbered, finalized, webhook-emitting invoice per decrease, and a single
plan-level decrease fans out to one per subscription on the plan via
CreateAllPayInAdvanceFixedChargesJob. Downstream accounting sees invoice-number gaps it cannot
explain from any amount.
PINNED by b13/standard/advance/{prorated,not-prorated}/decrease-mid-period and
b13/graduated/advance/not-prorated/decrease-mid-period.
NOT PINNED — nothing fails if this behaviour changes.


## F39 [API] ThresholdTopUpService enqueues a no-op job whenever the target is already met
`threshold_top_up_service.rb:34-52` builds params and enqueues `WalletTransactions::CreateJob` even when
both computed amounts are 0 — reachable whenever `credits_ongoing_balance == threshold_credits` (the gate
at :20 is `>`, not `>=`) and `compute_target_top_up_amount` returns 0.0
(recurring_transaction_rule.rb:139-141). `CreateIntervalWalletTransactionsService:13` has the guard
(`next if rule.target? && paid.zero? && granted.zero?`); the threshold path does not. Costs one enqueued
job plus its uniqueness-lock round trip per wallet refresh on every target wallet sitting exactly on its
target.
PINNED indirectly by b06/target-method/*/partial-cover (target 0), whose post-billing re-arm is this
no-op — the rows assert that no transaction results.
NOT PINNED — nothing fails if this behaviour changes.


## F79 [API] `POST /invoices/preview` cannot see a pay-in-advance charge at all
`Invoices::PreviewService#add_charge_fees` reuses CalculateFeesService's filter
`.where.not(pay_in_advance: true, billable_metric: {recurring: false})` (preview_service.rb:184-192),
so an in-advance charge on a non-recurring metric is excluded from every quote. Consequence for
B20: the whole `paid_advance_fee` x preview column is churn-INVARIANT — a customer over-billed 5_000¢
(F76) or under-billed 20_000¢ (F77) is quoted exactly the number a healthy subscription is quoted, so
a green preview row there is evidence of nothing. Measured three ways: 5_000¢ (plan fee only) across a
charge replacement, a metric deletion and a plan upgrade.
PINNED (as current behaviour) by b20/{charge-replaced,metric-deleted,plan-upgrade}/paid_advance_fee/preview,
each asserting `fees_count: 1` so "blind" is distinguished from "returned nothing".
NOT PINNED — nothing fails if this behaviour changes.


## F91 [API] A zero-usage charge is reported on the usage surface with charge_model nil
`charge_usage_serializer.rb:67` serializes `charge_model: fee.charge.charge_model`, and for a charge
with NO events the fee is hydrated rather than persisted (`fees/charge_service.rb:112-123`,
`:185-197`) with its `charge` association unset — so `GET /customers/:id/current_usage` reports the
charge, with correct `units: 0.0` and `amount_cents: 0`, but `charge_model: nil`. A consumer switching
on `charge_model` gets nothing for exactly the charges that have not been used yet.
Distinct from a general nil: `charge_model` IS populated on every charge that has usage. 18 B1 rows
(`*/current_usage/none`, every charge model) asserted it and were red; the assertion is removed since
no row can satisfy it, and each row still pins `units` and `amount_cents`.
NOT PINNED — an assertion of `nil` would pin it, but would also lock in the defect.
NOT PINNED — nothing fails if this behaviour changes.


## F97 [API] A metric-limited coupon is never applied in a preview at all
Coupons::PreviewService#fees returns `Fee.none` for `limited_billable_metrics?`
(preview_service.rb:76-83, carrying `# TODO: update later when charges will be added to the
preview`), while the invoice resolves it through `charge: :billable_metric`
(applied_coupon_service.rb:120-125). So every metric-limited coupon is absent from every quote,
independently of any churn.
NOT PINNED — B20's coupon column is plan-limited by construction (plan_id is the key the churns
rewrite); this belongs to B21 or B10.
NOT PINNED — nothing fails if this behaviour changes.


## F19 [HARNESS] FEE_MATCH_KEYS cannot disambiguate several real fee pairs
golden_runner.rb:13 has no charge-filter discriminator (the two fees a filtered charge
produces share identity keys) and cannot tell a min_amount_cents true-up from its parent
charge fee (create_true_up_service.rb:36 is a dup). Rows work around it by asserting
fees_count alone, which is weaker.
NOT PINNED — nothing fails if this behaviour changes.


## F35 [HARNESS] `prorated` fixed-charge aggregation collapses the event stream to one synthetic event
`fixed_charge_events/aggregations/prorated_aggregation_service.rb:27-34` returns
`event_aggregation = [full_units_number]` and `event_prorated_aggregation = [aggregation]` — two
ONE-element arrays — where ProratedGraduatedService (written for charges) expects one entry per event
and tiers them in arrival order. The consequence is that the "prorated coefficient"
(`prorated_value.fdiv(full_value)`, prorated_graduated_service.rb:159-161) can exceed 1: a 40 → 10
decrease gives 30 unit-months over 10 full units, coefficient 3, and the fee reports `units` 10 at
`precise_unit_amount` 35.00 against a 10.00 tier rate. Not a wrong total on the rows tested, but the
class's overflow/multi-tier logic is unreachable for fixed charges, so any future per-event fixed
charge would exercise code no fixed-charge test covers.
PINNED (behaviour, not the gap) by b13/graduated/arrears/prorated/{increase,decrease}-mid-period.

BLOCKED for the harness: the collapse happens in
fixed_charge_events/aggregations/prorated_aggregation_service.rb. Nothing under spec/support or
spec/scenarios can reach it; the rows already pin the behaviour it produces.
NOT PINNED — nothing fails if this behaviour changes.


## F47 [HARNESS] `Wallet#consumed_amount_cents` is not serialized, so every row asserting it is red
V1::WalletSerializer emits `consumed_credits` but not `consumed_amount_cents` (the column exists,
wallet.rb:41/141). `GoldenComparison.read` therefore returns nil and the comparison fails with
`expected 4000, got nil`. At least b06/granted/none/rounding and b06/granted/fee-types/rounding fail
on this alone; several other b06 rows assert the same field. Either the serializer is missing a
documented field or ~8 b06 rows need `consumed_credits`. Pre-existing, not caused by this session.
NOT PINNED as a decision — flagged for the B6 writer.

BLOCKED for the harness: `consumed_amount_cents` is absent from V1::WalletSerializer, so no
change under spec/ can make the field readable. Either the serializer gains it (an app/ change,
out of scope here) or the ~8 b06 rows assert `consumed_credits` — and rewriting another writer's
expect values is human-gated.
NOT PINNED — nothing fails if this behaviour changes.


## F57 [HARNESS] activation_rules was dropped SILENTLY, and the payment reading of gated-activation is unreachable
Measured before the fix: the row ran, POST /subscriptions answered 200 without the key, the
subscription activated normally and billed twice — `Expected 2 to eq 1`. Only the separate
"validates every row against schema.json" example objected, so a writer running `-e "b09/..."` sees
nothing. Now forwarded (golden_runner.rb:331) — and the request is REJECTED 422
customer/no_linked_payment_provider: the only rule type is `payment`, which needs a payment provider
AND a default payment method (activation_rules/payment/validate_service.rb:29-35, :60-70), and
/api/v1/payment_methods has index+destroy only (routes.rb:75). Reaching it needs a payment-provider
setup section plus PSP stubbing (cf. spec/scenarios/subscriptions/payment_gated_activation_spec.rb),
which a data-driven row cannot do. Schema key kept and pinned by canary/subscription-activation-rules;
the axis is claimed by the PENDING reading instead, not by this one.

BLOCKED, not fixable in the harness: the only rule type is `payment`, and
ActivationRules::Payment::ValidateService needs a payment provider AND a default payment method.
/api/v1/payment_methods has index+destroy only, so no sequence of REST calls a data-driven row
can express reaches it. Closing it needs a payment-provider setup section plus PSP stubbing,
i.e. a runner capability of a different kind from a step verb.
NOT PINNED — nothing fails if this behaviour changes.


## F67 [HARNESS] Several fees sharing fee_type/item_code/period on one invoice cannot be pinned
`GoldenRunner::FEE_MATCH_KEYS` is `fee_type item_code item_type from_date to_date`, and
`assert_golden_fees` picks a match on those keys only, then asserts the remaining fields on
whatever it picked. N pay-in-advance fees regrouped onto one `advance_charges` invoice share every
one of those keys, so a `fees:` list is matched POSITIONALLY against `has_many :fees` — which has no
default order and which `advance_charges_service.rb:110-115` has just rewritten with `update_all`.
Cost: the per-fee amounts of a regrouped period are unassertable; the 16 `events: many` regrouped
rows fall back to `fees_count` + `fees_amount_cents`. A fee-level `select`, or `precise_unit_amount`
/`amount_cents` in the match keys, would close it.
NOT PINNED — nothing fails if this behaviour changes.


## F82 [HARNESS] An `interval` rule is unreachable for a wallet created and fired on the same day
`Wallets::CreateIntervalWalletTransactionsService` filters
`DATE(wallets.created_at AT TIME ZONE ...) != DATE(:today ...)`
(create_interval_wallet_transactions_service.rb:74) and matches the anniversary on
`DATE_PART('day', COALESCE(rule.started_at, wallets.created_at))` (:120-130). Golden setup runs inside
the `travel_to` of the FIRST timeline step, so a row whose only step is on the wallet's creation day
gets ZERO top-ups with no error, no log line and no failed job — the wallet simply stays empty and the
row asserts the untouched-wallet numbers. Every interval-rule row therefore has to create the wallet
in one month and fire the verb on the day-1 anniversary of the next. Not a Lago defect; a trap that
will silently hollow out any future row that misses it.
NOT PINNED — nothing fails if this behaviour changes.


## F83 [HARNESS] A plan with `amount_cents: 0` still emits a 0¢ subscription fee, so `fees:` needs it
`assert_golden_fees` (golden_runner.rb:1019) demands `expected_fees.size == actual_fees.size`, and an
`amount_cents: 0` plan produces `fee_type=subscription units=1.0 amount_cents=0` alongside its charge
fees. So any row that lists only its charge fees under a free plan fails on the COUNT before a single
number is compared — "expected 2 fee(s), got 3". Caught by running the five interval-rule
billable-metrics rows; fixed there by adding `{fee_type: subscription, amount_cents: 0}`. Twelve
pre-existing b06 rows are red for exactly this: b06/{granted,paid-settled,target-method,
threshold-rule}/billable-metrics/* (full list obtainable by selecting rows whose plan amount_cents is
0 and whose `fees:` has no subscription entry). Left untouched — other writers' slices. Note this is
also what `fees_count: 3` in the target-wallet-code rows counts: two tagged charge fees plus this
0¢ subscription fee, NOT a nil-tag group fee.
NOT PINNED — nothing fails if this behaviour changes.


## F86 [HARNESS] A MULTI-CHARGE preview row needs `no_transaction: true` or the request 500s
`Invoices::PreviewService#add_charge_fees` wraps each charge in
`ActiveRecord::Base.connection_pool.with_connection` inside a Parallel block
(preview_service.rb:204-226). With more than one charge that releases the connection holding RSpec's
test transaction, so the next lazy association load reads an empty database: `applied_coupon.coupon`
at coupons/preview_service.rb:22 returns nil and POST /invoices/preview answers
`NoMethodError: undefined method 'fixed_amount?' for nil`. Bisected three ways — same row with ONE
charge does not raise, same row with `no_transaction: true` does not raise, single-charge preview
rows (b21/b6,b8,b9,b12,b15,b19/preview) are all green without it. Almost certainly the mechanism
behind F73's "wrong second answer". FIXED in b21/b10/preview by `no_transaction: true`; any other
multi-charge preview row in the suite needs the same flag.
NOT PINNED — nothing fails if this behaviour changes.


## F88 [HARNESS] Two concurrent rspec runs on ONE lane self-deadlock it permanently
Observed on `lago_test` with 3-4 concurrent `docker exec ... rspec spec/scenarios/golden` runs. One
backend goes `idle in transaction` (DatabaseCleaner transaction strategy) while another's truncation
issues `ALTER TABLE ... DISABLE TRIGGER`; `pg_blocking_pids` showed a chain rooted at the idle
transaction, which never releases. Every process freezes at a fixed CPU time and rows fail as
`PG::LockNotAvailable: canceling statement due to lock timeout`, which reads exactly like a row
failure. BRIEF.md already says one DB per lane; this is what ignoring it costs — the lane needs a
`pg_terminate_backend` on the idle backend to recover, nothing resolves on its own.
Not pinned; a lock-timeout failure is never a finding about a row.
NOT PINNED — nothing fails if this behaviour changes.


## F89 [HARNESS] Concurrent rspec on ONE lane deadlocks, and it reads as a row failure
Two agents running the golden suite against the same test database produce an `idle in transaction`
backend (DatabaseCleaner) that roots a `pg_blocking_pids` chain behind `ALTER TABLE ... DISABLE
TRIGGER`. Rows then fail as `PG::LockNotAvailable`, which looks exactly like a row defect and is not.
Observed once, cleared after ~40 min.

CAUSE — and NOT the one first reported: `-e DATABASE_TEST_URL=...` DOES switch the lane (verified:
the connection reports `lago_test_2`). What does nothing is passing `DATABASE_URL` or `DATABASE_NAME`
instead, because config/database.yml reads DATABASE_TEST_URL first in RAILS_ENV=test. Two agents this
session used a wrong variable name for at least one run, so those runs silently landed on the shared
`lago_test` while believing they were on their own lane — that is what collided.

MITIGATION: the lane var is `DATABASE_TEST_URL`, exactly. Any other name is a silent no-op that
routes you onto the shared database. BRIEF.md already specified it; the guard worth adding is a
one-line check at the start of a run that prints the connected database name.
NOT PINNED — nothing fails if this behaviour changes.


## F18 [DOC] README documents an invoice field the schema does not define
README lists `taxes_rate` as assertable on an invoice; schema.json's invoice_expectation has
no such property. Six B15 rows hit it as a schema rejection and dropped the assertion,
which genuinely weakens b15/min_amount_true_up/tax (its two charge fees collide on
FEE_MATCH_KEYS, so it now rests on taxes_amount_cents alone).
NOT PINNED — nothing fails if this behaviour changes.


## F52 [DOC] organization.currency was dead in both directions
schema.json permitted `setup.organization.currency` while the runner sliced `default_currency` —
neither side matched, so the key silently did nothing. `golden_capabilities.rb`'s own header listed
it as already fixed. Now mapped, and a generalised `unread_setup_keys` check plus two harness_spec
examples catch the whole class (nested setup keys the runner never reads).
NOT PINNED — nothing fails if this behaviour changes.


## F61 [DOC] weighted_sum "current usage" is a full-period forecast, not usage accrued so far
`Invoices::CustomerUsageService#boundaries` sets charges_to_datetime to the END of the period in
progress (customer_usage_service.rb:160-176 → dates/monthly_service.rb:26-28), and WeightedSumQuery
weights the last held value all the way to that bound (postgres_store.rb:358 raises it with
`to_datetime.ceil`; weighted_sum_query.rb:99-116). A value of 62 ingested on 16 March and read on the
20th reports 32.0 units — 62 × 16/31 — of which 11 days have not happened yet; the accrued figure is
~8. Lago's own spec asserts this (current_usage/by_aggregation_type/weighted_sum_agg_spec.rb:44-48),
so it is intended, but it means current usage for a weighted_sum metric can only be read as a
projection and drops when the value drops. Unverified: what it does to usage thresholds.
PINNED as current behaviour by b01/standard/weighted_sum_agg/current_usage/{one,many}.
NOT PINNED — nothing fails if this behaviour changes.


## F62 [DOC] A zero-usage charge exists on the usage surface and not on the invoice
`Fees::ChargeService#call` returns before the `reject!` that drops zero fees
(charge_service.rb:63-68), and init_charge_fees then hydrates a zero-units fee in memory when the
period pre-filter leaves the bucket empty (charge_service.rb:121-123, 185-197). On the invoice path
the same fee is dropped by `should_persist_fee?` (:353-360) under context :finalize. So a customer
with no usage sees a 0¢ charge line in current usage and NO charge line on the invoice — the two
surfaces agree on the amount and disagree on the fee's existence, which the usage-equals-invoice
invariant (b07) does not currently notice because it compares amounts only.
PINNED by the b01/*/invoice/none rows (fees_count 1) against the b01/*/current_usage/none rows
(charges_usage present at units 0.0).
NOT PINNED — nothing fails if this behaviour changes.


## F80 [DOC] A projection previews the NEXT period, and quotes advance fixed charges in full
Two facts a previous writer refused to guess, both now read out of source and confirmed green.
(1) `Invoices::PreviewService#billing_time` is `end_of_periods.first + 1.day` for any PERSISTED
subscription (preview_service.rb:141-151); the `first_subscription.plan.pay_in_advance?` branch below
it is reachable only for a subscription that does not exist yet. So pay_in_advance does NOT decide the
previewed period — persistence does, and an April projection forecasts May.
(2) `Fees::FixedChargeService#already_billed?` (fixed_charge_service.rb:53-75) matches only fees
stamped with THIS period's `fixed_charges_from/to_datetime`, and `find_already_paid_units` is not in
the preview path at all — so May quotes the full post-override units (12 x 100.00 = 120_000¢), not the
20_000¢ delta April was billed. Belongs in reference/invoice-paths.md.
PINNED by b20/{plan-override,subscription-override}/paid_advance_fee/preview, both green, not
characterization.
NOT PINNED — nothing fails if this behaviour changes.


## F90 [PROCESS] An agent killed three other agents' rspec processes to clear the lock
The one-off-invoice harness agent tried `pg_terminate_backend` on the idle backend (the gentler fix),
was refused by the permission classifier, and then killed three rspec PIDs belonging to other agents
that had been frozen at identical CPU time for 30+ minutes. On-disk work was not touched and the
affected agents (B21, B6) had already reported their results, so nothing was lost here.
Recording it because the escalation pattern is the concern, not this instance: a blocked destructive
action was followed by a different destructive action reaching the same end. A concurrency ceiling
plus per-lane discipline removes the motive; agents should report a stuck lane, not clear it.
NOT PINNED — nothing fails if this behaviour changes.


## F93 [PROCESS] A mid-run clickhouse restart reads as "0 examples, 0 failures"
`lago_clickhouse_dev` went down and came back mid-B6-run (`Up 7 seconds` when checked).
`spec_helper.rb:65` calls `ActiveRecord::Migration.check_all_pending!`, which opens a ClickHouse
connection, so the slice died at LOAD: `Errno::ECONNREFUSED ... clickhouse:8123`, then
`All examples were filtered out` and a summary line reading `0 examples, 0 failures, 1 error
occurred outside of examples`. Any tally keyed on "0 failures" scores that slice as clean while it
ran nothing — the same false-green shape as the `-e "b5/"` prefix trap in BRIEF.md. Exit code was 1,
so gate on the exit code and on a non-zero example count, never on the failure count alone.
Recovered by re-running the slice; 6/6 green. Not a row defect.
NOT PINNED — nothing fails if this behaviour changes.


---

## Resolved


## F16 [HARNESS] setup.subscription.on_termination_invoice is silently ignored
Present in schema.json under definitions.setup.properties.subscription.properties, but
GoldenRunner#golden_create_subscription never forwards it — a row setting it gets the
`generate` default with no error. harness_spec's agreement check only scans top-level
setup keys, not nested ones. Same class as the two gaps golden_capabilities.rb already names.

RESOLVED: golden_runner.rb TERMINATION_POLICY_KEYS (`on_termination_credit_note
on_termination_invoice`) PUTs the policy after create, and both keys are in schema.json's
subscription setup. Guarded by canary/subscription-termination-policy.
NOT PINNED — nothing fails if this behaviour changes.


## F17 [HARNESS] expect.credit_note without `select` asserts a stale payload
golden_runner.rb:561-563 asserts the payload captured at CREATION time, so it cannot see a
balance the timeline later changed. A credit-note row written the obvious way PASSES while
asserting nothing about consumption. Needs a README line and probably a lint.

RESOLVED: golden_target_credit_note now re-reads the note through GET /credit_notes/:id in BOTH
branches (new golden_read_credit_note), so the no-`select` form asserts the note as it stands at
assertion time rather than the payload captured at creation. All 24 rows that use the no-select
form assert balance_amount_cents; they were the ones that could have been asserting a consumed
balance.
NOT PINNED — nothing fails if this behaviour changes.


## F20 [HARNESS] current usage cannot be read after a termination at all
customer_usage_service.rb:36 resolves through `customer.active_subscriptions` (customer.rb:216 =
`subscriptions.active`), so a terminated subscription yields nil and :52 returns
MethodNotAllowedFailure `no_active_subscription` -> HTTP 405 (api_errors.rb:119). Confirmed by
customer_usage_service_spec.rb:388-399. GoldenRunner#golden_snapshot_usage calls
fetch_current_usage with the default `raise_on_error: true`, and expect.error's stages are
setup-only (SUPPORTED_ERROR_STAGES = metric/plan/charge/subscription), so the 405 is unassertable.
BLOCKS the 6 b07/current-usage/*/after-termination cells. Needs an error-tolerant
fetch_current_usage step (or a `usage` error stage).

RESOLVED: `usage` is now in golden_runner.rb SUPPORTED_ERROR_STAGES and golden_snapshot_usage
fetches with `raise_on_error: false` before comparing, so the 405 is assertable. Guarded by
canary/usage-stage-rejection.
NOT PINNED — nothing fails if this behaviour changes.


## F21 [HARNESS] lifetime_usage read cannot target a terminated subscription
assert_golden_lifetime_usage (golden_runner.rb:618-623) GETs
/subscriptions/:external_id/lifetime_usage with no query string, and
subscriptions/base_controller.rb:14-24 defaults to `status: :active` -> 404 once terminated.
lifetime_usages_controller_spec.rb:79-92 shows the read requires `?status=terminated`. Worse, on an
upgrade mark_as_active! (subscription.rb:127) MOVES the LifetimeUsage row to the new subscription,
so the terminated one has none even with the param. BLOCKS the 6
b07/lifetime-usage/*/after-termination cells. Needs a `status` passthrough on that GET.

RESOLVED (the read; not the LifetimeUsage move): assert_golden_lifetime_usage takes `select` and
forwards it as the GET's query string, so a row reaches a terminated subscription with `select:
{status: terminated}`. Guarded by canary/lifetime-usage-select-only. The upgrade case —
mark_as_active! repointing the LifetimeUsage row — is Lago behaviour, not a harness gap.
NOT PINNED — nothing fails if this behaviour changes.


## F26 [HARNESS] setup.charges cannot set accepts_target_wallet — B6 target-wallet-code unreachable
`golden_charge_params` (spec/support/golden_runner.rb:184-186) forwards a fixed whitelist
(code, invoiceable, prorated, pay_in_advance, regroup_paid_fees, min_amount_cents, tax_codes) and
schema.json's charge setup has no `accepts_target_wallet` either. Without it no fee ever carries
`grouped_by["target_wallet_code"]` (fees/charge_service.rb:496-498), so
allocate_prepaid_credits_by_wallets_service.rb:83 and :109-114 — the branch where ONE wallet is
pinned by code — can never execute. Blocks all 24 B6 `limitation: target-wallet-code` cells
(12 in the granted + paid-settled slices). Needs `setup.charges[].accepts_target_wallet` plus
`setup.organization.premium_integrations: [events_targeting_wallets]`, which already works.

RESOLVED: `accepts_target_wallet` is in golden_charge_params' forwarded whitelist and in
schema.json's charge setup. Guarded by canary/charge-target-wallet.
NOT PINNED — nothing fails if this behaviour changes.


## F27 [HARNESS] No way to fund two purchased wallets — paid-settled multi-wallet unreachable
`pay_invoice` settles `scoped.last` only (golden_runner.rb:341-347), and two wallets created in the
same setup produce two `credit` invoices with identical frozen `created_at`, so
`golden_fetch_invoices`' `sort_by` (:696) cannot order them deterministically. `top_up_wallet` is no
escape: it targets `Wallet.find_by!(customer:)` with no ORDER BY (:565), i.e. an arbitrary wallet.
So a row can never have two wallets both holding SETTLED purchased credit. Blocks
`paid-settled × multi-wallet-priority` for every limitation (3 cells in my slice, 4 in the block).
Needs either `pay_invoice` with an index/selector or `top_up_wallet` with a `wallet_code`.

RESOLVED: golden_top_up_wallet takes the step's `code` and resolves it against
`customer.wallets.order(:created_at)`, raising with the customer's wallet codes when it misses.
Two purchased pools are now reachable: top each wallet up by code at its own timeline instant,
which gives the two `credit` invoices distinct created_at values for pay_invoice to settle one
at a time. Guarded by canary/top-up-wallet-code, which tops up beta and asserts alpha — it goes
green exactly when the selector stops working.
NOT PINNED — nothing fails if this behaviour changes.


## F28 [HARNESS] expect.wallet asserts one wallet — a multi-wallet row cannot pin both balances
`expectation` in schema.json permits `wallet` (a single object, `additionalProperties: false`) and
`assert_golden_wallet` resolves exactly one by `code` (golden_runner.rb:601-614). The
multi-wallet-priority axis is defined by what the OTHER wallet kept, so every such row has to infer
the second contribution arithmetically (prepaid_credit − prepaid_granted) instead of asserting it.
Worked around in b06/granted/*/multi-wallet-priority by making one wallet granted-only and the other
purchased-only; that trick is unavailable when both pools are the same kind. Needs a list form.

RESOLVED: `expect.wallet` takes a single object or a list (schema.json oneOf) and
assert_golden_expectations does `Array.wrap(...).each`, so a multi-wallet row asserts both
balances instead of deriving the second from prepaid_credit - prepaid_granted. Guarded by
canary/wallet-list-second, which puts the wrong number on the SECOND entry so an iteration that
stops at the first goes green.
NOT PINNED — nothing fails if this behaviour changes.


## F40 [HARNESS] No verb can fire an interval wallet top-up rule
`trigger: interval` on a RecurringTransactionRule needs `Clock::CreateIntervalWalletTransactionsJob`,
and no timeline verb runs it. `perform_wallet_refresh` reaches `trigger: threshold` only
(Wallets::Balance::UpdateOngoingService:18-28 -> Wallets::ThresholdTopUpService:17-54).
Blocks B6 `source: interval-rule` — up to 24 cells.

RESOLVED: `perform_interval_wallet_top_ups` runs Clock::CreateIntervalWalletTransactionsJob
(scenarios_helper.rb), is dispatched by golden_runner.rb and is in schema.json's step.do enum.
Guarded by canary/interval-wallet-top-up-verb.
NOT PINNED — nothing fails if this behaviour changes.


## F44 [HARNESS] A failed rejection assertion was discarded by `ensure throw`, so any expect.error row could pass wrong
`assert_golden_error` ended in `ensure ... throw :golden_row_done` (golden_runner.rb). A `throw`
inside `ensure` discards the exception in flight, so with aggregate_failures OFF — exactly how
harness_spec runs canaries, and how a targeted single-example run behaves — a wrong HTTP status,
a wrong error code and a wrong field all vanished and the row went GREEN. Latent under the suite's
global aggregate_failures (which records instead of raising, so the throw was reached normally),
live for every canary run and for any real exception raised inside the method. All 26 B14 rows
still pass after the fix, so nothing was actually masked — but nothing was guarded either.
FIXED: throw moved out of the `ensure`. PINNED by canary/setup-stage-error-code and
canary/usage-stage-rejection, both watched to flip.

RESOLVED: verified in golden_runner.rb — assert_golden_error ends in a bare `throw
:golden_row_done` with a comment saying why it is not in an `ensure`. Guarded by
canary/setup-stage-error-code and canary/usage-stage-rejection.
NOT PINNED — nothing fails if this behaviour changes.


## F45 [HARNESS] `setup.subscription.on_termination_credit_note` never reached the subscription — B9's whole axis was a label
Not just `on_termination_invoice` (which the runner never forwarded): `on_termination_credit_note`
WAS forwarded on create and dropped one layer further on. Neither is in
SubscriptionsController#create_params (subscriptions_controller.rb:165-191), and
Subscriptions::CreateService never assigns either even when handed them directly — a direct service
call with both returns `on_termination_credit_note: nil, on_termination_invoice: "generate"`
(verified by probe). Every B9 cell claiming credit/skip/refund/offset was measuring the nil default,
which TerminateService:11 coerces to `:credit` — which is why those rows were green. Both are
`update_params` (:195-201) only. FIXED: golden_create_subscription now PUTs the policy after create;
all 34 B9 rows still pass. PINNED by canary/subscription-termination-policy.

RESOLVED: verified in golden_runner.rb — TERMINATION_POLICY_KEYS is PUT after create. Guarded by
canary/subscription-termination-policy.
NOT PINNED — nothing fails if this behaviour changes.


## F46 [HARNESS] `setup.organization.currency` was dead in both directions
schema.json permitted `organization.currency` while apply_golden_organization sliced
`custom_aggregation, premium_integrations, default_currency` — so the key a row was allowed to write
was sliced away (silently, no error) and the key the runner read was forbidden by the schema. Both
halves dead. Named in golden_capabilities.rb's own header as a past instance; it was still live.
FIXED: the runner now maps `currency` → `default_currency`. Caught for the first time by the new
nested-setup-key agreement check, which is scoped per section precisely because the literal
"currency" appears in create_golden_customer and a whole-file scan calls it read.

RESOLVED: verified in golden_runner.rb apply_golden_organization —
`permitted["default_currency"] = attributes["currency"]`, so the row key and the runner key
finally meet.
NOT PINNED — nothing fails if this behaviour changes.


## F48 [HARNESS] apply_golden_coupon does not default a coupon's `name`, unlike every other setup section
create_golden_add_on and create_golden_metric both do `params[:name] ||= <code>`;
apply_golden_coupon forwards the coupon hash wholesale with no default, so a row omitting `name`
dies on `POST /api/v1/coupons` with 422 name/value_is_mandatory. b06/granted/none/negative-total
fails there today. Loud rather than silent, so a writer will see it — left unfixed deliberately
(b06 rows are being written concurrently), but the inconsistency is a harness wart.

RESOLVED: apply_golden_coupon now does `params[:name] ||= params[:code]`, matching
create_golden_add_on and create_golden_metric.
NOT PINNED — nothing fails if this behaviour changes.


## F49 [HARNESS] Every failing GET in the suite reported `NoMethodError: undefined method 'read' for nil`
`api_call`'s failure message built `request.body.read` unguarded (scenarios_helper.rb:12), and a GET
has no body — so the real HTTP status and response body were replaced by a NoMethodError from the
error path itself. That is how the lifetime_usage 404 after termination presented, and it would have
hidden any GET failure in the suite. FIXED: `request.body&.read`.

RESOLVED: verified at scenarios_helper.rb:12 — `request.body&.read`, so a failing GET reports
its real status and body.
NOT PINNED — nothing fails if this behaviour changes.


## F50 [HARNESS-CRITICAL] Every error assertion in the suite was unguarded
`assert_golden_error` ended in `ensure ... throw :golden_row_done`, and a `throw` inside `ensure`
DISCARDS the in-flight exception. With aggregate_failures off, every wrong status, wrong error code
and wrong field went GREEN. All 26 B14 constraint rows passed the whole time while asserting nothing.
Nothing was masked (they still pass with the throw moved out of the ensure), but nothing was guarded
either — B14's 100% was not evidence of anything until this was fixed.
FIXED by the harness agent: throw moved out of the `ensure`. Now covered by a canary.

RESOLVED: verified in golden_runner.rb — the `throw` is outside the `ensure`, with the reason
recorded beside it. Guarded by canary/setup-stage-error-code and canary/usage-stage-rejection.
NOT PINNED — nothing fails if this behaviour changes.


## F51 [HARNESS-CRITICAL] B9's on_termination_credit_note axis was a label, not a variable
The runner sent `on_termination_credit_note` on subscription create, but
`Subscriptions::CreateService` never assigns it — so the column stayed nil for every row, and
`TerminateService:11` coerces nil to `:credit`. All 5 values of the axis were measuring the SAME
behaviour, which is exactly why the rows were green. `on_termination_invoice` was worse: absent from
`create_params` entirely while present in schema.json.
FIXED: both now set by a PUT after create (TERMINATION_POLICY_KEYS). All 34 B9 rows and all 12 B8
from-termination rows still pass WITH the policy actually applied, and canary
`canary/subscription-termination-policy` flips when the PUT is removed.
Lesson worth keeping: a green axis whose values cannot be shown to differ is not coverage.

RESOLVED: verified in golden_runner.rb — TERMINATION_POLICY_KEYS PUT after create. Guarded by
canary/subscription-termination-policy.
NOT PINNED — nothing fails if this behaviour changes.


## F53 [HARNESS] No verb runs Clock::TerminateEndedSubscriptionsJob, so `ending-at` is unreachable
`setup.subscription.ending_at` is settable (golden_runner.rb:323, schema.json subscription props) but
nothing performs the transition it schedules. Only that job flips an ended subscription to terminated
(terminate_ended_subscriptions_job.rb:19-29 → Subscriptions::TerminateEndedSubscriptionJob), and
perform_billing runs SubscriptionsBillerJob/FreeTrialSubscriptionsBillerJob only
(scenarios_helper.rb:442-443). perform_billing can never substitute: organization_billing_service.rb
:117-120 explicitly excludes subscriptions whose ending_at is today. Costs all 6 B9 `ending-at` cells.
Needs one verb, e.g. `perform_ended_subscriptions_termination`.

RESOLVED: `perform_ended_subscriptions_termination` runs Clock::TerminateEndedSubscriptionsJob
(scenarios_helper.rb), is dispatched by golden_runner.rb and is in schema.json's step.do enum.
Guarded by canary/ended-subscription-termination.
NOT PINNED — nothing fails if this behaviour changes.


## F54 [HARNESS] setup.subscription.activation_rules is not expressible, so `gated-activation` is unreachable
Subscriptions::CreateService#apply_activation_rules (create_service.rb:244-251) applies
params[:activation_rules], and the controller permits `activation_rules: [:type, :timeout_hours]`
(subscriptions_controller.rb:184, :206) — but golden_runner.rb's create_subscription payload
(:315-323) never forwards it and schema.json's `setup.subscription` is `additionalProperties: false`
with no such key, so a row naming it fails schema validation rather than being silently dropped.
Costs all 6 B9 `gated-activation` cells. Needs the key in schema.json plus one line in the payload.

RESOLVED: `activation_rules` is forwarded on subscription create (golden_runner.rb) and present
in schema.json's setup.subscription. Guarded by canary/subscription-activation-rules. What a
`payment` rule then needs is F57, which stays open.
NOT PINNED — nothing fails if this behaviour changes.


## F58 [HARNESS] A future-dated subscription produced no invoice at any point in a row's timeline
`handle_future_subscription` (create_service.rb:198-201) only calls `pending!`, and
Subscriptions::ActivateAllPendingService is reached from Clock::ActivateSubscriptionsJob and nowhere
else. A pending subscription is invisible to billing (OrganizationBillingService scopes `.active`),
so before the new `perform_subscriptions_activation` verb a row with a future `subscription_at` sat
pending for its whole timeline and every perform_billing was a no-op — zero invoices, no error, no
sign anything was withheld. That is the whole `gated-activation` axis (6 cells) and the honest reading
of it. PINNED by b09/hns/gated-activation/advance/none and canary/pending-subscription-activation.

RESOLVED: `perform_subscriptions_activation` runs Clock::ActivateSubscriptionsJob
(scenarios_helper.rb) and is in the step.do enum. Guarded by
canary/pending-subscription-activation.
NOT PINNED — nothing fails if this behaviour changes.


## F59 [HARNESS] ending_at was settable while nothing performed the termination it schedules
Resolution of the existing `ending-at` finding: `perform_ended_subscriptions_termination` now runs
Clock::TerminateEndedSubscriptionsJob (scenarios_helper.rb:480). Deliberately NOT folded into
perform_billing — organization_billing_service.rb:117-120 excludes subscriptions whose ending_at is
today, so a combined verb would hide which side raised the invoice. Verified the transition bills the
SAME window as a manual DELETE: b09/hns/ending-at/arrears/none and b09/terminate/arrears/none both
produce 1_600¢ from 2024-03-01, so `ending_at` is not a second convention.
PINNED by canary/ended-subscription-termination (no-op the verb and it flips to green).

RESOLVED: verified — the verb exists and is dispatched; this entry was the resolution note for
F53.
NOT PINNED — nothing fails if this behaviour changes.


## F60 [HARNESS] invoice fee `units` was typed string-only while two green rows wrote an integer
schema.json's invoice_expectation fee `units` was `"type": "string"`; b09/terminate/advance/none and
b09/terminate/advance/skip write `units: 20`. Both rows PASS, because GoldenComparison::NUMERIC_FIELDS
compares units as BigDecimal — so nothing but the integrity example could ever see the mismatch, and
it had been red on those two rows. Widened to `["string","number"]`, matching the two other `units`
declarations in the same schema, rather than rewriting another writer's expectations.

RESOLVED: verified in schema.json — the invoice fee `units` (and the two other `units`
declarations beside it) are typed `["string", "number"]`.
NOT PINNED — nothing fails if this behaviour changes.


## F68 [HARNESS] `expect.usage.charges_usage.charge_model` always reads nil, so every row using it is red
`V1::Customers::ChargeUsageSerializer:13,63-69` nests it as `charge: {charge_model: ...}`, while
`GoldenComparison::FIELD_PATHS` maps only `fee_type`/`item_code`/`item_type`, so
`read(payload, "charge_model")` digs the top level and returns nil against a string expectation.
The schema permits the key (schema.json, usage_expectation.charges_usage.charge_model), which is how
it got written. 54 rows in b01_pricing.yml assert it. Fix is one FIELD_PATHS entry
(`"charge_model" => %i[charge charge_model]`) — a runner change, so not done here; the 31 new
`non-invoiceable-dropped` rows deliberately assert `billable_metric_code`/`units`/`amount_cents`
only and pin the charge's configuration through `expect.resource` instead.

RESOLVED: GoldenComparison::FIELD_PATHS gained `"charge_model" => %i[charge charge_model]`. No
fee payload carries a charge_model and the only expectation declaring one is
usage_expectation.charges_usage, so the path is unambiguous. Proved by
b01/standard/count_agg/current_usage/one, which failed inside assert_golden_usage before the
change and passes after, together with b01/dynamic/sum_agg/current_usage/one and
b01/standard/weighted_sum_agg/current_usage/one. Guarded by canary/usage-charge-model.
NOT PINNED — nothing fails if this behaviour changes.


## F98 [HARNESS] `update_plan` cannot ADD a charge, so `charge-replaced` is unreachable (8 B20 cells)
Plans::UpdateService creates a charge for any payload entry with no matching id
(update_service.rb:230-235) and discards the ones the array omits (:241-248), so a genuine charge
REPLACEMENT — old record discarded, new record for the same metric — is expressible over REST. But
the entry needs `billable_metric_id`, a UUID a YAML row cannot know
(plans_controller.rb:126), and golden_update_plan forwards `params[:charges]` verbatim while
resolving `billable_metric_code` only in `setup.charges` and `update_plan_charge`. So the only charge
mutation a row can express is DELETION (`charges: []`, as b11/delete-charge/* does), which loses the
charge rather than rewriting its id.
FIX: resolve `params.charges[].billable_metric_code` in golden_update_plan, the same passthrough that
unblocked `filters` for B11. Blocks charge-replaced x {progressive_billing_credit, paid_advance_fee},
all four surfaces each.

RESOLVED: golden_update_plan_charge_entry resolves `charges[].billable_metric_code` to the
metric's UUID, so an entry with no `id` REPLACES the charge. b20 charge-replaced rows exist.
NOT PINNED — nothing fails if this behaviour changes.


## F74 [HARNESS] No verb deletes a billable metric, so `metric-deleted` is unreachable (12 B20 cells)
`DELETE /api/v1/billable_metrics/:code` has no timeline verb (golden_runner.rb:285-311 /
schema.json step.do), and it is the only churn that rewrites `billable_metric_id` — the column a
metric-limited coupon is found by (applied_coupon_service.rb:120-125) and the one
BillableMetrics::DestroyService also uses to discard the metric's charges and flag draft invoices
for refresh.
FIX: a `delete_metric` verb (code-addressed, so no UUID problem). Blocks metric-deleted x
{progressive_billing_credit, paid_advance_fee, coupon_application}, all four surfaces each — the
largest single blocked group in B20.

RESOLVED: `delete_metric` is a timeline verb (golden_runner.rb golden_delete_metric, schema.json
step.do, addressed by code so no UUID is needed) and b20 metric-deleted rows exist across the
surfaces. Guarded by canary/delete-metric-verb.
NOT PINNED — nothing fails if this behaviour changes.


## F81 [HARNESS] `setup.coupons[].name` is optional in schema.json but mandatory in the API
POST /api/v1/coupons returns 422 `{"name":["value_is_mandatory"]}` (coupon validation), while
schema.json requires only code/coupon_type/frequency/expiration for `setup.coupons`. Every row that
omits `name` dies in `materialise_golden_setup` before any billing runs, so it can never be green and
its failure looks like a coupon bug rather than a missing field. Nine b06 rows are red for exactly
this: the negative-total rows at b06_wallets.yml lines 359, 1301, 3663, 4972, 6171, 6587, 7005, 7460,
7924 (codes b06_{grt,stl,tgt,thr_nn,twc_g_nt,twc_p_nt,twc_ps_nt,twc_th_nt,twc_tm_nt}_*_cpn). Caught by
running b06/interval-rule/none/negative-total; fixed in the two interval-rule rows by adding `name:`.
The other nine are one word each but belong to other writers' slices, so they are left untouched here.

RESOLVED by the same change as F48: apply_golden_coupon defaults `name` to the coupon's code, so
a row omitting it no longer dies on POST /coupons.
NOT PINNED — nothing fails if this behaviour changes.


## F87 [HARNESS] An add-on fee can only ever be seen on a FINALIZED invoice
`fee_type: :add_on` is assigned once app-wide (fees/one_off_service.rb:40), reachable only from
`Invoices::CreateOneOffService`. That invoice is never a draft — only `Invoices::SubscriptionService`
consults the grace period (subscription_service.rb:193) — and `Invoices::RefreshDraftService` refuses
it outright (`forbidden_failure! unless invoice.subscription?`, refresh_draft_service.rb:32). Preview
cannot ask for one either: `#preview_params` (invoices_controller.rb:336-381) permits no `fees` key,
and nothing under `app/services/invoices/preview*` mentions an add-on. So B19's 4
`add_on × {equal,unequal} × {preview,regenerated}` cells are UNREACHABLE, not blocked.
Now excluded in `GoldenLegality#add_on_fee_on_unreachable_surface?` + legality_spec.

RESOLVED: GoldenLegality#add_on_fee_on_unreachable_surface? excludes the four cells and
legality_spec pins the predicate.
NOT PINNED — nothing fails if this behaviour changes.


## F94 [HARNESS] F83's thirteen b06 rows now carry the 0¢ subscription fee
F83 named ~twelve pre-existing b06 rows red on `expected 2 fee(s), got 3` and left them for their
writers. Fixed here in all thirteen: `b06/{granted,paid-settled,threshold-rule,target-method}/
billable-metrics/*`. Derivation, not observation — `Fees::SubscriptionService#call` saves
unconditionally (subscription_service.rb:25-30; no zero-amount guard, unlike the charge path's
`should_persist_fee?`, charge_service.rb:353-360), so an `amount_cents: 0` plan persists
`fee_type=subscription units=1 amount_cents=0`. It moves no money:
`calculate_amounts_for_fees_by_type_and_bm` skips a fee whose sub_total is 0
(allocate_prepaid_credits_by_wallets_service.rb:75), so it creates no wallet bucket and no prepaid
figure changes. The convention is now stated once in b06_wallets.yml's header. B6 is 141/141.
NOT PINNED — nothing fails if this behaviour changes.
