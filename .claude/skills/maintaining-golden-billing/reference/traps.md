# Things that cost an hour here

Consulted when something surprises you, not read every time — the judgment is in SKILL.md. Every entry
below was paid for once already.

## Arithmetic that is not where you would look for it

**Credit notes are shared between fees by weight, and the weight can be zero.**
`credit_note_service.rb#apply_credit_to_fees` gives each fee
`credit x (amount_cents - precise_coupons_amount_cents + taxes_amount_cents) / invoice_total`. Two
consequences that have both bitten here: a fee whose `precise_coupons_amount_cents` equals its amount
weighs NOTHING and the whole credit note lands on the others — which is exactly what the progressive
clamp does to a charge fee; and because a limited wallet's ceiling is
`sub_total + taxes - precise_credit_notes`, that weighting silently decides how much of the wallet
may be spent. Never assume a credit note spreads by gross fee amount; three rows here were first
written that way and all three were wrong.

**A fee whose amount depends on other fees is computed before every reducer.** The minimum-commitment
true-up reads raw `amount_cents` in the producer phase, so a coupon applied afterwards discounts the
commitment rather than being absorbed by the headroom under it. Any row mixing a true-up with a
reducer has to say which side of that line it is asserting — `fees_amount_cents` is identical either
way, and only the per-fee split tells them apart.

**Write the control row in the same sitting.** Every finding here got sharp only when paired with a
row where the same machinery behaves correctly: `b17/pb-tax-wallet/invoice` is what narrowed the tax
defect from "progressive billing plus tax" to "plus anything that reduced what the threshold invoice
collected", and it did so by passing. A characterization row alone records a symptom; with its
control it names a trigger.

## The rest

- **Premium hides in four places, and each is silent.** `Charges::CreateService` drops `invoiceable`,
  `regroup_paid_fees` and `min_amount_cents` without a licence; `Customers::CreateService` drops
  `invoice_grace_period` and `timezone`. All return HTTP 200. A row testing one of those validations
  without `premium: true` passes for the wrong reason. Credit notes, manual payments and
  `graduated_percentage` are premium outright; `custom_agg` needs the `custom_aggregation` org flag,
  not the licence.
- **Money that has not moved cannot move.** `regroup_paid_fees` only collects *succeeded* fees;
  purchased wallet credits are unusable until the top-up invoice is settled; a refund credit note is
  rejected on an unpaid invoice. The first two fail silently.
- **Some fields are nested.** `invoice_grace_period` and `document_locale` live under
  `billing_configuration` in both request and response; sent top-level they are dropped by strong
  params. Asserting the top level would pass for the wrong reason either way.
- **`PUT /plans/:code/charges/:code` is a full replacement.** Resend `charge_model` even when only
  `properties` change. It also does not flag draft invoices for refresh, unlike `PUT /plans/:code`.
- **A draft carries no coupon, no credit note and no prepaid credit** (the gate is in
  invoice-paths.md's surface table), so a grace-period draft is fees plus tax and nothing else — it
  showed 12_000¢ for a period billed at 4_400¢ in one B17 row. Any row asserting a draft must assert
  those three fields as 0 rather than omitting them.
- **Finalization recomputes unconditionally; the refresh flag only gates the CLOCK.** So
  `Charges::UpdateService` not setting that flag delays a correction rather than losing it: the draft
  stays stale (15_000¢) and the issued invoice carries the new price (35_000¢). Before calling a
  missing flag a lost edit, check what finalization does.
- **`to_credit_amount` reads the LAST threshold invoice, net of its own coupons but not of credits
  granted against it.** With two demands of 6_000¢ and 13_000¢, the period invoice credits 13_000¢,
  not 7_000¢ and not 19_000¢ — `invoice.progressive_billing_credits` are credits pointing AT that
  invoice, of which a threshold invoice has none. Getting this wrong double-credits or under-credits
  every multi-threshold period.
- **Repricing a charge between two threshold invoices re-rates the whole period.** The second demand
  bills cumulative usage at the NEW price and credits only the cash the first collected at the old
  one, so the customer pays the new price for units metered before the change.
- **Shortening a grace period issues the drafts immediately.**
  `Customers::UpdateInvoiceIssuingDateSettingsService:24-32` walks the customer's drafts and enqueues
  `Invoices::FinalizeJob` for each. So "set grace to 0 and observe the draft" is not a reachable
  state; reach that cell by EXTENDING the period instead.
- **Preview dies on a plan whose charge has no usage in the period.** Three separate nils in one
  path — `date_diff_with_timezone`, `taxes`, `fixed_amount?` — because the fee built for a zero-usage
  charge in preview lacks its associations. One is fixed (`create_true_up_service.rb` computed a
  prorated minimum even for charges without one); the rest are open. Symptom is a 500 from
  `POST /invoices/preview`, so if a preview row dies rather than disagrees, check whether every charge
  has usage before suspecting your row.
- **The two termination paths disagree about the boundary day.** Terminating an ARREARS subscription
  on the 16th bills THROUGH the 16th (`b09/terminate/arrears/none`: 16 days of a 31-day March).
  Terminating an ADVANCE subscription on the 16th credits FROM the 16th, treating it as unused
  (`b09/upgrade/advance/credit`: 15 of 30 days). Both are coherent — the upgrade only adds up because
  the new subscription also starts on the 16th — but they are opposites, and assuming the arrears
  rule in an advance row is off by exactly one day.
- **Upgrade and downgrade are opposite behaviours behind one endpoint.** `POST /subscriptions` with
  a dearer plan terminates immediately, credits the unused part and bills the new plan pro rata; with
  a cheaper plan it creates a PENDING subscription and changes nothing until the period ends. Which
  one you get is decided solely by the price.
- **An applied coupon snapshots its terms.** `AppliedCoupon` copies amount, percentage, frequency and
  duration at application time, so editing the coupon changes future applications only. A row
  expecting a live discount to follow the coupon is asserting a read-through that does not exist.
- **Rows write `invoice_grace_period` flat**; the runner nests it under `billing_configuration`,
  which is what the API requires in both directions. Same for `document_locale`. One helper does the
  nesting for both `setup.customer` and the `update_customer` step, so do not hand-nest in a row.
- **Fixed charges are posted after the plan** — inlining them in `POST /plans` returns 500. Add-ons
  reject `amount_cents: 0`.
- **`ScenariosHelper` helpers take their payload positionally.** Bare keyword syntax is swallowed by
  `**kwargs` and fails as `wrong number of arguments (given 0, expected 1)`, which does not point at
  the call site. Brace the hash.
- **Progressive billing needs `no_transaction: true`** — it runs inside an `idempotent_transaction`.
- **The suite is intermittently flaky, and the cause is not yet known.** Three consecutive full runs
  of the same 128 examples, in RSpec's deterministic defined order, gave 2 failures, then 3 on
  *different* rows, then 0. None were assertion failures: `PG::TRDeadlockDetected`, a nil
  `organization` mid-example, a subscription that vanished. So **before treating a failure as a
  finding, re-run it alone.** A row that passes in isolation and fails in the suite is this, not a
  regression — and a green full run is not proof either.
  Unproven lead: `no_transaction` rows switch DatabaseCleaner to `:deletion`, and
  `spec_helper.rb:203-207` then gives the `EventsRecord` connection a `NullStrategy`, so a row that
  both ingests events and deletes tables has two sessions on one database. That matches the symptoms
  and the flakes began when B15 took the count of such rows from 2 to 4 — but nothing has been
  measured, and the nine dev worker containers were checked and are on `lago`, not `lago_test`.
  Worth an hour before the suite is trusted in CI.
- **A credited fee gives back its share of the coupon.** Crediting 6_000¢ of a 10_000¢ fee that
  carried a 2_000¢ coupon yields a 4_800¢ credit note, not 6_000¢.
- **`offset_amount_cents` is not "credit notes issued against this invoice".** Only
  `CreditNotes::CreateFromProgressiveBillingInvoice`'s sibling `create_from_termination` sets it, so
  it reads 0 for every other automatic credit note. Assert the credit note itself instead — that is
  what `expect.credit_note.select` exists for.
- **Canaries do not get row metadata.** `premium: true` becomes RSpec metadata in `golden_spec.rb`,
  which the canary path bypasses; a premium-gated canary used to fail on the licence check and count
  as working. `run_canary` handles it now, but anything else added to that metadata needs the same
  treatment.
