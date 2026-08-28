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
