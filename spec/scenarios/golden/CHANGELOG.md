# Golden billing suite changelog

Append one entry per `expect:` change: row id, old → new, the commit that changed the behaviour, and
one line of why. See `.claude/skills/maintaining-golden-billing/SKILL.md`.

An entry with no named commit is only valid for a restoration — putting a row back to what its own
`math:` derives. Any other unexplained change means the row should have stayed red.

## b15/coupon/progressive_billing — restoration, no commit

`coupons_amount_cents` 3000 → 0, `progressive_billing_credit_amount_cents` 10000 → 7000,
`sub_total_excluding_taxes_amount_cents` 2000 → 8000, `total_amount_cents` 2000 → 8000, and a second
invoice expectation added.

The row was written on a mis-derivation, never green, and never described real behaviour: it assumed
both reducers meet on one invoice and commute. They do not. The threshold invoice is finalized before
the period invoice exists, so a `frequency: once` coupon is consumed there, and the credit carried
forward is `fees_amount_cents - coupons_amount_cents` (`progressive_billed_amount.rb`) rather than the
amount billed. Re-derived from those two sources before re-running, not fitted to output.

## b20/plan-upgrade/commitment_progress/invoice, /draft, /regenerated, b20/plan-upgrade/coupon_application/regenerated — restoration, no commit

Each row's `fees:` list gains `{fee_type: subscription, amount_cents: 0}`.

These rows were authored but never executed. On their first-ever execution (2026-08-31) they failed:
Lago persists a 0¢ subscription fee for a plan with `amount_cents: 0`, and `assert_golden_fees`
requires the `fees:` list to be exhaustive against `fees_count`, so the missing entry was the only
thing wrong. Amounts and `fees_count` were already correct on all four rows; only the omitted fee was
added, per row: invoice's March/termination/plan-B invoices (sub 0 + charge 3000 + commitment 27000;
sub 0 + charge 3000 + commitment 13000; sub 0 + charge 8000), draft (sub 0 + 3000 + 13000), regenerated
(sub 0 + 4000 + 12000), and coupon_application/regenerated (sub 0 + charge 10000).

## b20/plan-upgrade/commitment_progress/preview — restoration, no commit

`preview.fees_count` 1 → 2, and the `math` sentence claiming preview "adds a subscription fee only
where the plan has an amount" rewritten.

Row was written on a mis-derivation, never green, and never described real behaviour: that claim had
no basis in the implementation. `Invoices::PreviewService#add_subscription_fee`
(preview_service.rb:170-182) always builds the subscription fee once `should_create_subscription_fee?`
(preview_service.rb:379-383) passes — there is no amount gate — so the preview builds the same two fees
(0¢ subscription + charge) that the real invoice persists. Re-derived from the implementation before
re-running, not fitted to output.

## b15/charge/progressive_billing — restoration, no commit

`progressive_billing_credit_amount_cents` 7000 → 2000, `sub_total_excluding_taxes_amount_cents` 0 →
5000, `credit_notes_amount_cents` 0 → 5000 on the subscription invoice; `credit_amount_cents` 3000 →
8000 on the credit note.

The row was written on a mis-derivation, never green, and never described real behaviour: its own
"OTHER ORDER" paragraph already stated the correct mechanism (should_persist_fee? drops the zero-usage
charge's fee at `context: :finalize`, progressive_billing_service.rb:102) but the row's main
expectations and its stated conclusion contradicted that paragraph — asserting that a fee dropped from
persistence still contributes its charge_id to
`progressive_billing_invoice.fees.charge.pluck(:charge_id)` (progressive_billing_service.rb:26-31).
The cap only ever counts what was persisted, so it is charge_a's period fee alone (2_000¢), and the
8_000¢ excess becomes a credit note (5_000¢ applied to this invoice, 3_000¢ held available). Re-derived
from the two cited services before re-running, not fitted to output.

## b08/from-progressive-billing-excess/credit/with-tax — restoration, no commit

`fees_count` 1 → 2 and `{fee_type: subscription, amount_cents: 0}` added to the subscription
invoice's `fees:` list.

Same derivation error as the four b20 plan-upgrade rows corrected the same day: the row was authored
but never executed, and its first-ever execution (2026-08-31) failed only on the omitted 0¢
subscription fee that Lago persists for a plan with `amount_cents: 0`. Every other assertion —
including the credit note's pre-tax-measured/post-tax-issued gross-up that is the row's point — was
probe-verified correct before this change.

## b19/charge/equal/preview — F101, F72/F73 withdrawn

`taxes_amount_cents` 0 → 4000, `sub_total_including_taxes_amount_cents` and `total_amount_cents`
25000 → 29000; `characterization` and `pins: [F72, F73]` removed.

The row characterized a harness artifact as Lago behaviour. The preview prices charges in parallel
worker threads, and under the :transaction cleaning strategy only one pool connection could see the
example's data — so the multi-charge preview's output was a per-thread draw (F101), and F72/F73 were
measurements of that draw. On committed data the preview is deterministic and equals the row's own
29_000¢ forecast, so the expectations now assert the forecast. GoldenMatrix forces `no_transaction`
onto every previewing row for the same reason.
