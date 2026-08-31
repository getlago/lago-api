---
name: maintaining-golden-billing
description: Use when a row in spec/scenarios/golden is failing, when extending billing coverage, when new billing behaviour has shipped, when the ledger reports blocked or surface-blind blocks, when working a lead from leads.yml, or when tempted to change an expected value to get CI green. Carries reference/invoice-paths.md (which invoices can be a draft, and what each surface applies) and reference/traps.md.
---

# Maintaining the golden billing suite

## Overview

`spec/scenarios/golden` asserts exact expected values against Lago's REST API. Its entire worth is
whether a wrong number makes it fail. Everything below protects that one property.

**A failing row is a finding, not a chore.**

Read `spec/scenarios/golden/README.md` for how the suite works. This skill is only the judgment the
tooling cannot make for you — the lints, canaries and `harness_spec.rb` already enforce the mechanical
rules, and you do not need to re-check them by hand.

## The rule that is not negotiable

Never change an `expect:` value to turn a red row green unless you can name the commit that
intentionally changed **that specific behaviour**. When you can, in the same edit you must:

1. re-derive `math:` from the implementation — rewrite the reasoning, do not retype the number
2. append to `spec/scenarios/golden/CHANGELOG.md`: row id, old → new, the commit, one line of why
3. say so in your report

Without that evidence the row stays red and is reported as a suspected regression.

**Violating the letter of this rule is violating the spirit of it.** A suite that can rewrite its own
baselines is worth less than no suite, because it converts "we are covered" from a fact into a habit.

## Eight judgments the tooling cannot make

### 1. Regression, or intended change?

`dev/golden/report.rb` sorts failures by whether a commit since the last green run touched the
block's services. That is a **hint, not proof** — a regression is by definition introduced by a
commit touching the service that owns the behaviour, so section ② is exactly where a real regression
will land.

Evidence means: you read the diff and it changes the arithmetic the failing **field** measures. A
commit that touched the same directory is not evidence. No commit, or a commit that does not touch
that field → treat it as ①, report it, leave it red.

### 2. Would this row fail if Lago were wrong?

Before accepting a green row, ask: **what incorrect implementation would still pass it?** If several
would, the row records a number without guarding anything.

The sharpest instance: three pay-in-advance rows each ingested a single event, and a single event
cannot distinguish per-event pricing from a cumulative delta. They passed for a year's worth of
plausible-looking reasons and the doctrine written beside them was simply wrong.

Event cardinality is an axis (`none`, `one`, `many`) for this reason. Zero events still bills tier-1
`flat_amount`; one event collapses `max_agg`, `sum_agg` and `latest_agg` to the same answer.

### 3. For an interaction, the order IS the behaviour

`Invoices::CalculateFeesService` applies features in a fixed sequence
(`calculate_fees_service.rb:42-63`):

```
producers   subscription → charge → fixed_charge → non_invoiceable → commitment_true_up
            ↓ fees_amount_cents
reducers    progressive_billing → coupon → TAX → credit_note → prepaid_credit
```

Two features interact exactly when both are present and that order decides the amount. B15's cells
are the derived product of such pairs, not a list somebody wrote.

Worked example — `coupon × tax`, 10_000¢ of fees, a 4_000¢ fixed coupon, 20% VAT. The coupon applies
first, so the taxable base is 6_000¢, tax is 1_200¢, total **7_200¢**. Taxing first would give
**8_000¢** — the customer pays 800¢ more for the same invoice.

Two consequences for any interaction row:

- **Say what the other order would give**, in `math`, with its number.
- **Choose amounts where the two differ.** A percentage coupon would commute with tax and the row
  would prove only that the features co-existed. And assert the intermediate fields —
  `sub_total_excluding_taxes_amount_cents` and `taxes_amount_cents` — because `fees_amount_cents` is
  identical under both orders.

**The two stages may never meet on one invoice.** Progressive billing precedes coupons in the list
above, and it is still the coupon that lands first — because the threshold invoice is finalized
before the period invoice exists, and a `frequency: once` coupon is spent there. Reading the stage
order alone gets this backwards. Before deriving a pair, ask which invoices exist and when; if the
answer is two, `expect.invoice` takes a list and the row must assert both sides. Asserting one is how
a reducer that moves money out of view passes for correct.

### 4. Two features, or a stack?

A pair asks which of two stages runs first. **Three or more asks something a pair cannot see**:
whether a stage is still handed the right base after everything before it has already moved it.
B15 is pairs, B17 is stacks (derived subsets of the reducer list), and the difference is not
academic — the tax defect in `b17/full-stack/invoice` needs a credit note, a coupon AND progressive
billing on one invoice to appear, and every pair row involved is green.

When a stack row disagrees with your derivation, **the invoice-level fields and the fee-level fields
are separate arithmetic**. `taxes_amount_cents` follows the sum of the FEES' bases, not the invoice's
`sub_total_excluding_taxes_amount_cents`. If a stage moves one and not the other, tax silently
follows the fees. Assert `fees:` with `taxes_amount_cents` per fee when a tax figure surprises you —
that is what localised it here.

### 5. One of it, or two?

B19 exists because two instances of the same feature ask something one cannot: do they add, or do they
compete — and if they compete, which is consumed first and therefore which **survives to the next
period**. Three arrangements, and the middle one is where rows go wrong:

| arrangement | what it must prove |
|---|---|
| `equal` | two instances both take effect and add |
| `unequal` | the consumption ORDER changed the outcome |
| `capped` | together they exceed the pool, and the allocation decided who got what |

**Two instances of the same size usually commute, and a row built that way proves nothing.** Two
5_000¢ coupons against 10_000¢ of fees discount 10_000¢ in either order, and the leftover is
`sum − fees` regardless. The order only becomes visible when something makes one instance unable to
use its full value — a coupon limited to a billable metric whose fee is smaller than the coupon, a
wallet limited to a fee type, a credit note weighted onto a fee that carries nothing. Build that in
deliberately or the cell is decoration.

**A second period is usually required.** `frequency: once` does not mean "one invoice", it means
"until exhausted": `should_terminate_applied_coupon?` needs `credit_amount >= remaining_amount`
(`applied_coupon_service.rb:78-85`). So a partially-used coupon comes back, and a coupon the loop
never reached comes back untouched — `applied_coupons_service.rb:28` breaks out as soon as the
sub_total hits zero. Both look identical on the first invoice and differ entirely on the second.

The orderings themselves are single clauses in single services and are guarded by
`legality_spec.rb`'s multiplicity block, so a refactor that drops one fails there rather than
silently turning every B19 row into a coincidence.

### 6. Which surface is being asked?

An invoice, a draft, a preview and a regenerated invoice are four different computations of the same
period, and they do not share code. Preview reimplements the pipeline in
`Invoices::PreviewService#compute_tax_and_totals`; a draft is recomputed by
`Invoices::RefreshDraftService` only when something flagged it `ready_to_be_refreshed`. So "does this
feature work" has up to four answers, which is why B17 and B18 carry `observed_via` as an axis.

**Before writing any row that asserts a draft, refreshes an invoice, or reasons about a grace period,
read `reference/invoice-paths.md`.** Its headline is that a grace period belongs to the service that
raised the invoice, not to the customer — which decides, per invoice, whether a draft is reachable at
all.

**A row that asserts a draft must be paired with the same row minus the mutation.** A draft that was
never a draft passes while testing nothing, and the failure is indistinguishable from the bug you were
chasing. The BIL-537 pair is the model: identical rows, one refreshed and one not, and the control is
what turns "the fee is missing" into "the refresh deleted it".

**Every block needs at least one non-finalized row, and `rake golden:ledger` now names the blocks that
have none.** Not as a fourth axis on every block — multiplying 1,149 cells by four surfaces would
mostly produce cells where draft and final provably agree. As a rule with a report: a block that has
only ever read finalized invoices is blind to a third of its own behaviour.

BIL-537 is what that costs. B13 covers a fixed-charge units change 36 ways — four charge models,
prorated and not, advance and arrears, three kinds of units change — and cannot see the bug, because
not one of those rows holds an invoice open long enough to refresh it. The units change is correct;
what a REFRESH makes of it is a different question, and B13 never asks it.

### 7. Is the math derived, or copied?

`math:` is the only thing letting a reviewer check a number without running anything, so a
confidently wrong `math:` is worse than none. Derive it from the implementing service — open
`app/services/charge_models/…`, `app/services/fees/…` — not from a row that happens to be green, and
never by generalising from one observation.

### 8. Extend the harness, or work around it?

Extending is allowed. Write the **failing row first**: it is the justification for the capability and
becomes the regression test for it. A new assertion kind ships with its canary in the same change —
an assertion nobody has watched fail is indistinguishable from one that cannot fail.

Check `rake golden:ledger` before starting: it separates cells that are blocked on capability from
cells that are merely unwritten, and names what each blocked group needs.

## Investigating a reported gap

When someone says *"we never test X with Y"*, they have noticed a **pattern**, not a point. Five
steps:

**1. Locate.** Translate the description into a block and a cell, then grep `SCENARIOS.md` for it.
Feature pairs are B15 (`coupon × prepaid_credit`); a charge-model/aggregation combination is B1. If
the cell already shows `~`, it is guarded by a spec outside the suite — say where, and stop. A
duplicate row is worse than none.

**2. Probe.** To find out what Lago actually does, write a throwaway row with `/probe/` in its id and
run it. Never a side-channel script: the harness has canaries proving its assertions can fail, a
script has nothing, and a finding confirmed by a script nobody kept is indistinguishable a month
later from a finding nobody checked.

**3. Derive.** Read the implementing service and write `math` that explains the number rather than
recording it. For an interaction, the pipeline order is the behaviour — say what the *other* order
would produce, and choose amounts where the two differ. If they do not differ, the row proves the
features co-existed, not that they were applied in sequence.

**4. Widen.** Cover the reported cell, its **siblings** (the same parent, last axis varying) and the
**symmetric** cell if the axes are of the same kind. Stop there. "Similar" means adjacent in the
tree, not everything that felt related.

**5. Clean up.** Delete every `/probe/` row. A lint fails the suite if one survives.

## Rationalizations — every one of these was actually made here

| Excuse | Reality |
|---|---|
| "The test just wasn't updated when the change landed" | Then name the change. A commit in the same directory is not the same change. |
| "Two other engineers already agreed it's a stale test" | Agreement is not evidence. The diff is evidence. |
| "The row passes, so the behaviour is confirmed" | A one-event row passes under several different implementations. Ask what would also pass. |
| "The release is blocked" | A wrong expectation ships wrong billing. Red is the correct state until explained. |
| "It's just prose, not an assertion" | Wrong prose in `math:` or the README is copied into the next fifty rows. Three README claims here were false. |
| "I'll note the coverage gap and move on" | If it is blocked, say what capability it needs. If it is writeable, it is a row somebody can write today. |
| "The edit obviously applied" | One edit here silently did not, and the wrong code was blamed for an hour. Grep for the change. |
| "I'll write one row for the reported gap" | Its siblings are the same setup for a third of the cost, and the gap was reported because someone saw a pattern. |
| "The interaction row passes, so the order is right" | Check the other order's number. If it matches, the row proves co-existence, not sequence. |
| "Both features are on the invoice, so I'll assert the invoice" | Ask how many invoices exist. A threshold or top-up invoice is finalized earlier and can absorb the whole effect. |
| "The row passes when I run it on its own" | Run the block, then the suite. Deletion-strategy rows (`no_transaction`) share a second DB connection and interfere. |
| "It should be a draft, the customer has a grace period" | Check which service raised that invoice. Most of them finalize regardless — see reference/invoice-paths.md. |
| "The row asserts a draft and it passed" | Check the draft was ever a draft. A dropped `invoice_grace_period` finalizes immediately and the row passes having tested nothing. |
| "Preview disagrees with the invoice, so preview is broken" | Check which of its four contexts you asked for. A proposal is not a projection. |
| "Two of the same feature is just a bigger one of it" | Then the row commutes and proves nothing. Make one instance unable to spend its full value. |
| "The surface variants of a covered cell are just copies" | Draft, preview and invoice ran the same period to 12_000¢, 4_400¢ and 4_400¢. Derive each. |
| "I'll fit the expectation to what it returned" | Only as a `characterization: true` row that names the defect, the line responsible, and the number the derivation gives. |
| "The mutation ran and nothing moved, so the feature is broken" | Check whether that write flags drafts for refresh at all. `PUT /plans/:code/charges/:code` does not; `PUT /plans/:code` does. |
| "I'll add the assertion kind now and the canary after" | An assertion nobody has watched fail is indistinguishable from one that cannot fail. Same change or not at all. |

## Things that cost an hour here

`reference/traps.md` — fifteen entries, each paid for once. Read it when a number surprises you.

## Quick reference

| Task | Command |
|---|---|
| Run the suite | `dev/golden/run.sh rspec spec/scenarios/golden` |
| One row | add `-e "b01/volume"` |
| Coverage, risk, blocked cells | `dev/golden/run.sh rake golden:ledger` |
| New behaviour since baseline | `dev/golden/run.sh rake golden:discover` |
| Three-section report + proposal | `ruby dev/golden/report.rb` (host — needs git) |
| Regenerate COVERAGE.md, SCENARIOS.md, scenarios.json | `dev/golden/run.sh rake golden:docs` |

`annotate` rewrites `app/models/*.rb` on every run; `git checkout -- app/models/` before staging.

**The generated docs are build products, not committed files.** `scenarios.json`, `SCENARIOS.md`,
`FINDINGS.md` and `COVERAGE.md` are gitignored; run `rake golden:docs` whenever you need a current
copy to read, and never stage one. `harness_spec.rb` checks the generator against the rows directly,
so nothing depends on a committed inventory being fresh.

Read endpoints are out of scope by decision, not oversight (`actions.yml` says why). Do not add rows
asserting pagination, filtering or serializer shape; that is request-spec work.

## Findings

A finding is a defect the suite knows about. `spec/scenarios/golden/findings.yml` is the master —
severity, title, evidence, triage status — and `FINDINGS.md` beside it is **generated** from it by
`rake golden:docs`. Edit the ledger; anything typed into the markdown is overwritten.

Three commands, three different questions:

| | |
|---|---|
| `rake golden:findings` | which findings are pinned by a row, and which are prose |
| `rake golden:triage` | what is NEW or CHANGED since the ledger was signed off |
| `rake golden:findings:export` | regenerate the markdown (also run by `golden:docs`) |

**Recording a defect is three things, not one:** `characterization: true` on the row, `pins: [F<n>]`
on the row, and the entry in the ledger. Miss the second and `triage` lists it as UNTRACKED — a defect
recorded only inside the row that happens to assert it. Miss the third and the suite fails, because a
new finding is the one thing in a run worth reading.

**The number to watch is not coverage, it is how many findings nothing pins.** A finding with no row
holding it still is an anecdote: the next refactor moves the behaviour, in either direction, and
nobody is told. Today that is 76 of 94 open findings.

**`changed` is sharper than `new`.** The digest fingerprints the assertions of every row pinning a
finding, so rewording `math` is free and moving a number is not. A known defect whose numbers moved was
either partly fixed or got worse; accepting the new figures silently is how a characterization row
becomes a rubber stamp.

## Reporting

Answer three questions in order, and never let the third go missing because the first two are clean:

1. **Not performing as expected** — failures with no commit that explains them
2. **Changed** — failures a named commit does explain, with the commit
3. **Not covered** — new behaviour from `discover`, plus the ranked writeable gaps

Then propose changes and **ask before applying them**, showing `old → new` per field. `none` is
always a valid answer and leaves the suite red.

Claim nothing you have not run. "Tests pass" without the output beside it is not a report.
