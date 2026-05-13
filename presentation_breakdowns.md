# Invoice v4 Presentation Breakdowns

This document describes how `presentation_breakdowns` should be rendered in the
Invoice v4 PDF. The rendering lives in a **dedicated partial** that is reused
across templates by passing in the list of fees to render breakdowns for.

## New Partial

Create a new Slim partial:

- Path: `app/views/templates/invoices/v4/_presentation_breakdowns.slim`
- Locals: `fees` (an array/relation of `Fee` records).
- Responsibility: render the full presentation breakdowns block (per-charge
  header + title rows + breakdown rows) for the given `fees`.

The partial owns:

- The "no displayable keys → render nothing" guard.
- The per-charge grouping (`group_by(&:charge_id)`).
- The title row rules (`grouped_by` empty → "Total", `charge_filter_id`
  present → charge filter value, otherwise grouped_by values).
- The breakdown row rules (use full `displayable_keys`, render nil as
  `<none>`, sort with `<none>` at the end).
- The table layout (reusing `.breakdown-details` / `.breakdown-details-table`).

The partial **does not** decide which fees to include — that responsibility
belongs to the caller (e.g. `_subscription_details.slim` passes `filtered_fees`,
other templates may pass their own equivalent list).

### Calling the partial

From any v4 template that has access to a fees collection:

```slim
== SlimHelper.render('templates/invoices/v4/_presentation_breakdowns', self, fees: filtered_fees)
```

Inside `_subscription_details.slim` specifically, call it **after** the
proration notice block (the existing code that does not change):

```slim
- if fees.first.charge.prorated?
  .alert.body-3 = I18n.t('invoice.notice_prorated', days_in_month: number_of_days_in_period)
- else
  .alert.body-3 = I18n.t('invoice.notice_full')

/ NEW: render presentation breakdowns for the subscription
== SlimHelper.render('templates/invoices/v4/_presentation_breakdowns', self, fees: filtered_fees)
```

Other v4 templates that have an equivalent fees list (e.g. `_charge.slim`,
`_fixed_charge.slim`, `_one_off.slim`) can reuse the same partial by passing
their own fees collection. See the "Validation Flow" section below for which
templates should call it.

## Data Source

The partial expects `fees` to already contain the right set of fees. It then
filters to only what's relevant for breakdowns:

- Keep only `fee.charge?` fees.
- Keep only fees that have `fee.presentation_breakdowns.any?`.
- Group the remaining fees by `charge_id`.

The caller is responsible for providing fees that are eager-loaded with
`presentation_breakdowns` to avoid N+1 queries. In `_subscription_details.slim`,
`filtered_fees` already satisfies this via:

```ruby
base_fees = subscription_fees(subscription.id).includes(..., :presentation_breakdowns)
```

### Displayable Keys

- Source of truth: `Charge#presentation_group_keys_values_displayed_in_invoice`
- `displayable_keys = fees.first.charge.presentation_group_keys_values_displayed_in_invoice`
- If `displayable_keys` is blank, **render nothing** for that charge group.

## Rendering Rules (inside the partial)

### Header (Per Charge)

- Render once per charge group.
- Locale key: `invoice.presentation_breakdowns_header`
- Suggested interpolation: `charge` (use `fees.first.invoice_name`).

Example (conceptual):

- `I18n.t("invoice.presentation_breakdowns_header", charge: fees.first.invoice_name)`

### Fee Title Row

For each fee inside the charge group, render a title row before its breakdown rows.

Title text (values only):

1. If `fee.grouped_by.blank?`:
   - title = `I18n.t("invoice.presentation_breakdowns_total")` (i.e. "Total")
   - This applies even when `fee.charge_filter_id?` is present.
2. Else if `fee.charge_filter_id?`:
   - title = the charge filter value (the value that the fee's
     `charge_filter` represents — TBD which exact attribute to use).
3. Else:
   - title = `fee.grouped_by.values.compact.join(" • ")`

Units column:

- show `fee.units` on the right.

### Breakdown Rows

For each `PresentationBreakdown` in `fee.presentation_breakdowns`, render a row:

- Use the charge's full `displayable_keys` for every breakdown row.
  - We do **not** subtract `fee.grouped_by.keys`: if a key is displayable on the
    charge, its value must appear in the breakdown row regardless of whether the
    fee is also grouped by that key.
- Extract values in `displayable_keys` order from `breakdown.presentation_by`,
  supporting string/symbol keys:
  - `value = presentation_by[key] || presentation_by[key.to_sym]`
- Build the row label from **values only**, joined with ` • `.
- Null/blank values are rendered as the literal string `<none>` (so a breakdown
  like `{ "region" => "eu", "department" => nil }` renders as `eu • <none>`).
- Sort breakdown rows lexicographically by their extracted values array, but
  rows with any null/blank value are pushed to the **end** of the list (and
  among themselves they are still sorted by their non-null values).

Units column:

- show `breakdown.units` on the right.

### Table Layout

- Use the existing PDF styles used by other breakdowns in v4:
  - container: `.breakdown-details`
  - table: `table.breakdown-details-table`
- Keep a simple 2-column layout:
  - left: label/title
  - right: units

## Examples

All examples assume a charge `compute` with:

- `presentation_group_keys` that mark `region` and `department` as `display_in_invoice: true`
- so `displayable_keys = ["region", "department"]`

The per-charge header (rendered once per charge group) reuses
`I18n.t("invoice.presentation_breakdowns_header", charge: fees.first.invoice_name)`,
e.g. `Usage breakdown — compute`.

### Scenario 1: `fee.grouped_by` is empty (no charge filter)

State:

- `fee.charge_filter_id` is nil
- `fee.grouped_by` is `{}`
- `fee.units = 110`
- `displayable_keys = ["region", "department"]`
- `fee.presentation_breakdowns`:
  - `{ "region" => "eu", "department" => "engineering" }`, `units: 40`
  - `{ "region" => "us", "department" => "engineering" }`, `units: 35`
  - `{ "region" => "us", "department" => "sales" }`, `units: 25`
  - `{ "region" => "us", "department" => nil }`, `units: 10`

Title row: `I18n.t("invoice.presentation_breakdowns_total")` (i.e. "Total").

Rendered table (sorted lexicographically by values; nil values are rendered as
`<none>` and pushed to the end of the list):

| Label            | Units |
| ---------------- | ----- |
| Total            | 110   |
| eu • engineering | 40    |
| us • engineering | 35    |
| us • sales       | 25    |
| us • <none>      | 10    |

### Scenario 2: `fee.grouped_by` is present

State:

- `fee.charge_filter_id` is nil
- `fee.grouped_by = { "region" => "eu" }`
- `fee.units = 65`
- `displayable_keys = ["region", "department"]`
- `fee.presentation_breakdowns`:
  - `{ "region" => "eu", "department" => "engineering" }`, `units: 40`
  - `{ "region" => "eu", "department" => "sales" }`, `units: 20`
  - `{ "region" => "eu", "department" => nil }`, `units: 5`

Title row: `fee.grouped_by.values.compact.join(" • ")` → `eu`.

Rendered table (breakdown labels use the charge's full `displayable_keys`, so
`region` keeps appearing even though the fee is grouped by it; rows are sorted
lexicographically by values, and nil values are rendered as `<none>` and pushed
to the end of the list):

| Label            | Units |
| ---------------- | ----- |
| eu               | 65    |
| eu • engineering | 40    |
| eu • sales       | 20    |
| eu • <none>      | 5     |

### Scenario 3: `fee.charge_filter_id` is present (with `fee.grouped_by` empty)

State:

- `fee.charge_filter_id` is present (charge filter value: `eu`)
- `fee.grouped_by` is `{}`
- `fee.units = 50`
- `displayable_keys = ["region", "department"]`
- `fee.presentation_breakdowns`:
  - `{ "region" => "eu", "department" => "engineering" }`, `units: 30`
  - `{ "region" => "eu", "department" => "sales" }`, `units: 15`
  - `{ "region" => "eu", "department" => nil }`, `units: 5`

Title row: since `fee.grouped_by.blank?`, the title is
`I18n.t("invoice.presentation_breakdowns_total")` → "Total" (the
`charge_filter` value is **not** used here because the `grouped_by` rule wins
when `grouped_by` is empty). When `grouped_by` is present together with a
`charge_filter`, the title should use the **charge filter value** instead of
`fee.invoice_display_name` — the exact attribute to use is TBD.

Rendered table:

| Label             | Units |
| ----------------- | ----- |
| Total             | 50    |
| eu • engineering  | 30    |
| eu • sales        | 15    |
| eu • <none>       | 5     |

### Combined view (charge group with multiple fees)

When a charge group has multiple fees (e.g. one ungrouped fee, one grouped, and
one with a charge filter), the per-charge header is rendered once and each fee
contributes its own title row followed by its breakdown rows:

| Label             | Units |
| ----------------- | ----- |
| Total             | 110   |
| eu • engineering  | 40    |
| us • engineering  | 35    |
| us • sales        | 25    |
| us • <none>       | 10    |
| eu                | 65    |
| eu • engineering  | 40    |
| eu • sales        | 20    |
| eu • <none>       | 5     |
| Total             | 50    |
| eu • engineering  | 30    |
| eu • sales        | 15    |
| eu • <none>       | 5     |

## Locales (New Step)

Add new keys in every `config/locales/**/invoice.yml`:

- `invoice.presentation_breakdowns_header` (per-charge header)
- `invoice.presentation_breakdowns_total` ("Total")

Languages to update:

- `config/locales/en/invoice.yml`
- `config/locales/fr/invoice.yml`
- `config/locales/es/invoice.yml`
- `config/locales/de/invoice.yml`
- `config/locales/it/invoice.yml`
- `config/locales/pt-BR/invoice.yml`
- `config/locales/nb/invoice.yml`
- `config/locales/sv/invoice.yml`
- `config/locales/zh-TW/invoice.yml`

## Notes

- `presentation_breakdowns` are already eager-loaded for `filtered_fees` via:
  - `base_fees = subscription_fees(...).includes(..., :presentation_breakdowns)`
- The partial is invoked **once per call site**. In `_subscription_details.slim`
  it is invoked after the proration notice, outside the recurring-fees loop, so
  it runs once per subscription with the already-prepared `filtered_fees`.

## Validation Flow (Invoices::GeneratePdfService → v4 templates)

This section documents the full PDF generation flow for **v4 invoices only**
(`invoice.version_number >= 4`) and the scenarios that need to be tested to
ensure the new `_presentation_breakdowns.slim` partial is rendered when
expected.

### Entry point

`Invoices::GeneratePdfService#call` (`app/services/invoices/generate_pdf_service.rb`):

1. Guards: returns failure if the invoice is `nil` or `draft?`.
2. Calls `generate_pdf` which:
   - Switches locale to `invoice.customer.preferred_document_locale`.
   - Calls `Utils::PdfGenerator.call(template:, context: invoice)` which renders
     the Slim template selected by `#template`.
   - Optionally attaches FacturX XML when `should_generate_facturx_einvoice_xml?`.
   - Attaches the resulting PDF back to the invoice.

### Template selection for v4 invoices

`#template` returns one of the following templates (with `version_number = 4`):

| Condition (in order)                                                  | Template                       |
| --------------------------------------------------------------------- | ------------------------------ |
| `invoice.self_billed?`                                                | `invoices/v4/self_billed`      |
| `invoice.one_off?` (non self-billed)                                  | `invoices/v4/one_off`          |
| `charge?` (all fees `pay_in_advance?` AND `charge?`)                  | `invoices/v4/charge`           |
| `fixed_charge?` (all fees `pay_in_advance?` AND `fixed_charge?`)      | `invoices/v4/fixed_charge`     |
| default (any other case)                                              | `invoices/v4` (`v4.slim`)      |

> "Optional (TBD)": these templates do not reach `_subscription_details`, so to
> show breakdowns for them you would need to call
> `_presentation_breakdowns` directly from that template (e.g. from
> `_one_off.slim`, `_charge.slim`, `_fixed_charge.slim`) passing the relevant
> fees. Decide which of these should also display breakdowns.

### Per-template branches

This section lists every branch (rendering decision) inside each of the v4
top-level templates and the partials they delegate to. For each branch:

- **Branch (location)** — the slim conditional + approximate line number.
- **Condition** — the boolean that selects the branch.
- **Renders / Action** — the partial rendered or the fee/row action taken.
- **Needs change** — tick the box (`[x]`) once the branch has been wired up
  to render `_presentation_breakdowns` (or once you've decided no change is
  needed). Use this column to drive the integration work.

> Line numbers are approximate (based on the files at the time of writing).
> Re-check after any change to the templates.

#### `app/views/templates/invoices/v4/self_billed.slim`

| Branch (location)                                              | Condition                                                                                        | Renders / Action                                                | Needs change |
| -------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ | --------------------------------------------------------------- | ------------ |
| inline `if one_off?` (~L443-444)                               | `invoice.one_off?`                                                                               | `templates/invoices/v4/_one_off`                                | [ ]          |
| inline `elsif credit?` (~L445-446)                             | `invoice.credit?`                                                                                | `templates/invoices/v4/_credit`                                 | [ ]          |
| inline `elsif progressive_billing?` (~L447-448)                | `invoice.progressive_billing?`                                                                   | `templates/invoices/v4/_progressive_billing_details`            | [ ]          |
| inline `elsif subscriptions.count == 1` (~L449-450)            | not one_off + not credit + not progressive_billing + exactly 1 sub                               | `templates/invoices/v4/_subscription_details`                   | [ ]          |
| inline `else` (~L451-452)                                      | not one_off + not credit + not progressive_billing + `subscriptions.count > 1`                   | `templates/invoices/v4/_subscriptions_summary`                  | [ ]          |
| bottom `if subscriptions.count > 1` (~L468-469)                | `subscriptions.count > 1` (runs in addition to the `_subscriptions_summary` inline branch above) | `templates/invoices/v4/_subscription_details`                   | [ ]          |

#### `app/views/templates/invoices/v4.slim` (default)

| Branch (location)                                | Condition                                                                                        | Renders / Action                                                | Needs change |
| ------------------------------------------------ | ------------------------------------------------------------------------------------------------ | --------------------------------------------------------------- | ------------ |
| inline `if credit?` (~L462-463)                  | `invoice.credit?`                                                                                | `templates/invoices/v4/_credit`                                 | [ ]          |
| inline `elsif progressive_billing?` (~L464-465)  | `invoice.progressive_billing?`                                                                   | `templates/invoices/v4/_progressive_billing_details`            | [ ]          |
| inline `elsif subscriptions.count == 1` (~L466-467) | not credit + not progressive_billing + exactly 1 sub                                          | `templates/invoices/v4/_subscription_details`                   | [ ]          |
| inline `else` (~L468-469)                        | not credit + not progressive_billing + `subscriptions.count > 1`                                 | `templates/invoices/v4/_subscriptions_summary`                  | [ ]          |
| bottom `if subscriptions.count > 1` (~L485-486)  | `subscriptions.count > 1` (runs in addition to the `_subscriptions_summary` inline branch above) | `templates/invoices/v4/_subscription_details`                   | [ ]          |

#### `app/views/templates/invoices/v4/one_off.slim`

| Branch (location)                                | Condition                                       | Renders / Action                                                | Needs change |
| ------------------------------------------------ | ----------------------------------------------- | --------------------------------------------------------------- | ------------ |
| body render call (~L407)                         | always (no inner branching)                     | `templates/invoices/v4/_one_off`                                | [ ]          |

##### Branches inside `_one_off.slim`

| Branch (location)                                | Condition                                       | Renders / Action                                                | Needs change |
| ------------------------------------------------ | ----------------------------------------------- | --------------------------------------------------------------- | ------------ |
| `if one_off?` (~L8)                              | `invoice.one_off?`                              | iterate `fees.ordered_by_period`, render an add_on fee row per fee | [ ]          |

#### `app/views/templates/invoices/v4/charge.slim`

| Branch (location)                                | Condition                                       | Renders / Action                                                | Needs change |
| ------------------------------------------------ | ----------------------------------------------- | --------------------------------------------------------------- | ------------ |
| body render call (~L460)                         | always (subscription name header)               | `templates/invoices/v4/_subscription_name`                      | [ ]          |
| body render call (~L461)                         | always (charge body)                            | `templates/invoices/v4/_charge`                                 | [ ]          |

##### Branches inside `_charge.slim`

| Branch (location)                                                                | Condition                                                                                       | Renders / Action                                                | Needs change |
| -------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- | --------------------------------------------------------------- | ------------ |
| outer `fees.order(:succeeded_at, :created_at).each` (~L8)                        | always (iteration root)                                                                         | iterate every fee on the invoice                                | [ ]          |
| `if fee.fixed_charge?` → `next` (~L9-10)                                         | `fee.fixed_charge?`                                                                             | skip the fee                                                    | [ ]          |
| `if fee.charge.percentage? && fee.amount_details.present?` (~L11)                | percentage charge with amount_details                                                           | enter the percentage rendering sub-tree                         | [ ]          |
| └ `if fee.basic_rate_percentage?` (~L12-19)                                      | basic rate (single `rate` property on the filter/charge)                                        | render a one-row "basic percentage" fee row                     | [ ]          |
| └ `else` (~L20-38)                                                               | percentage charge with extra `amount_details` (graduated, etc.)                                 | render charge-name row + `templates/invoices/v4/_charge_percentage` | [ ]          |
| `else` (non-percentage) (~L39-66)                                                | charge that is not `percentage?` (or `amount_details` blank)                                    | enter the standard fee rendering sub-tree                       | [ ]          |
| └ `if !fee.charge.invoiceable?` (~L41-49)                                        | charge is not invoiceable (e.g. pay_in_advance non-invoiceable)                                 | name + filter + `succeeded_at` date                             | [ ]          |
| └ `elsif fee.charge.prorated?` (~L50-57)                                         | charge is prorated                                                                              | name + filter + proration breakdown text                        | [ ]          |
| └ `else` (~L58-66)                                                               | regular charge                                                                                  | name + filter + units + unit price                              | [ ]          |
| per-fee tail render (~L68)                                                       | always (per fee, after the row(s) above)                                                        | `templates/invoices/v4/_conversion_row`                         | [ ]          |

#### `app/views/templates/invoices/v4/fixed_charge.slim`

| Branch (location)                                | Condition                                       | Renders / Action                                                | Needs change |
| ------------------------------------------------ | ----------------------------------------------- | --------------------------------------------------------------- | ------------ |
| body render call (~L459)                         | always (no inner branching)                     | `templates/invoices/v4/_fixed_charge`                           | [ ]          |

##### Branches inside `_fixed_charge.slim`

| Branch (location)                                | Condition                                       | Renders / Action                                                | Needs change |
| ------------------------------------------------ | ----------------------------------------------- | --------------------------------------------------------------- | ------------ |
| `grouped_fees.each_with_index` (~L7)             | always (iteration root)                         | iterate each billing-period group                               | [ ]          |
| `next unless fee_group.fixed_charge_fees.any?` (~L8) | the billing-period group has no fixed_charge fees | skip that group                                             | [ ]          |
| inner `fee_group.fixed_charge_fees.each` (~L19)  | always (per group)                              | iterate fixed_charge fees in the group                          | [ ]          |
| per-fee render (~L20)                            | always (per fixed_charge fee)                   | `templates/invoices/v4/_fixed_charge_fee`                       | [ ]          |

### Scenarios to test

For each scenario below, build an invoice that exercises the listed flags and
verify whether the new partial is reached. Use
`Invoices::GeneratePdfService.new(invoice:).render_html` (or `.call`) and
assert on the resulting HTML/PDF.

1. **Standard subscription invoice, single subscription**
   - Setup: `invoice.version_number = 4`; not self-billed; not one_off; not
     credit; not progressive_billing; not all fees pay_in_advance; exactly 1
     subscription; at least one charge fee with `presentation_breakdowns`.
   - Expected template: `invoices/v4`.
   - Expected: `_subscription_details` is rendered **inline**, which calls
     `_presentation_breakdowns` with `filtered_fees`.
   - Validate: presentation breakdowns section renders for each charge that
     has `displayable_keys`.

2. **Standard subscription invoice, multiple subscriptions**
   - Setup: same as (1) but `subscriptions.count > 1`.
   - Expected template: `invoices/v4`.
   - Expected: `_subscriptions_summary` is rendered inline; then
     `_subscription_details` is rendered once at the **bottom** of the layout,
     which calls `_presentation_breakdowns`.
   - Validate: presentation breakdowns appear inside the bottom block.

3. **Self-billed invoice, single subscription**
   - Setup: `invoice.self_billed? = true`; not one_off; not credit; not
     progressive_billing; 1 subscription with breakdowns.
   - Expected template: `invoices/v4/self_billed`.
   - Expected: `_subscription_details` is rendered inline (and calls the
     partial).
   - Validate: breakdowns render and use the self-billed page chrome.

4. **Self-billed invoice, multiple subscriptions**
   - Setup: `invoice.self_billed? = true`; not one_off; > 1 subscriptions.
   - Expected template: `invoices/v4/self_billed`.
   - Expected: `_subscription_details` is rendered at the bottom (and calls
     the partial).
   - Validate: breakdowns appear inside the bottom block.

5. **Self-billed one-off invoice**
   - Setup: `invoice.self_billed? = true` AND `invoice.one_off? = true`.
   - Expected template: `invoices/v4/self_billed`.
   - Expected: branch uses `_one_off`; `_subscription_details` is **not**
     rendered. The partial is only reached if `_one_off` (or `self_billed.slim`
     itself) is updated to call it directly.
   - Validate: presence/absence of breakdowns depends on that decision (TBD).

6. **One-off invoice (non self-billed)**
   - Setup: `invoice.one_off? = true`, not self-billed.
   - Expected template: `invoices/v4/one_off`.
   - Expected: `_subscription_details` is **not** rendered. The partial is
     only reached if `one_off.slim` is updated to call it directly.
   - Validate: presence/absence of breakdowns depends on that decision (TBD).

7. **Pay-in-advance charge-only invoice**
   - Setup: all fees are `pay_in_advance?` AND `charge?`, not self-billed,
     not one_off.
   - Expected template: `invoices/v4/charge`.
   - Expected: `_subscription_details` is **not** rendered (uses `_charge`).
     The partial is only reached if `charge.slim` is updated to call it
     directly.
   - Validate: presence/absence of breakdowns depends on that decision (TBD).

8. **Pay-in-advance fixed-charge-only invoice**
   - Setup: all fees are `pay_in_advance?` AND `fixed_charge?`, not
     self-billed, not one_off.
   - Expected template: `invoices/v4/fixed_charge`.
   - Expected: `_subscription_details` is **not** rendered. The partial is
     only reached if `fixed_charge.slim` is updated to call it directly.
   - Validate: presence/absence of breakdowns depends on that decision (TBD).

9. **Credit invoice (`credit?`)**
   - Setup: `invoice.credit?` true (e.g. credit-only invoice), not self-billed,
     not one_off, 1 subscription.
   - Expected template: `invoices/v4`.
   - Expected: inline branch uses `_credit`; `_subscription_details` is **not**
     rendered inline. If `subscriptions.count > 1`, the bottom branch still
     renders it (and the partial).
   - Validate: no breakdowns inline; if multi-subscription, breakdowns appear
     only at the bottom.

10. **Progressive billing invoice (`progressive_billing?`)**
    - Setup: `invoice.progressive_billing?` true, 1 subscription, not
      self-billed, not one_off, not credit.
    - Expected template: `invoices/v4`.
    - Expected: inline branch uses `_progressive_billing_details`;
      `_subscription_details` is **not** rendered inline. Bottom branch still
      renders it when `subscriptions.count > 1`.
    - Validate: no breakdowns inline.

### Scenarios that must be validated inside the partial

Independent of the entry-template branch, the following sub-scenarios should
be tested whenever `_presentation_breakdowns.slim` is invoked:

- A charge whose `presentation_group_keys_values_displayed_in_invoice` is
  blank → renders **no** breakdown block for that charge.
- A charge with one displayable key.
- A charge with multiple displayable keys.
- A fee with `fee.grouped_by` blank (Title = "Total") — see scenarios 1 and 3
  above.
- A fee with `fee.grouped_by` present (Title = grouped_by values joined by
  ` • `) — see scenario 2 above.
- A fee with `fee.charge_filter_id` present (Title = charge filter value) —
  see scenario 3 above (with `grouped_by` present).
- Breakdowns containing nil values → rendered as `<none>` and pushed to the
  end of the list.
- Breakdowns with composite presentation keys (e.g. `{department, region}`)
  → label values are joined by ` • ` in `displayable_keys` order.
- Multiple fees within the same charge_id group → single per-charge header,
  multiple title + breakdown blocks under it.
- Subscription with multiple charges → multiple per-charge headers.
- Empty `fees` array passed in → the partial renders nothing.

### How to exercise the flow in specs

- `Invoices::GeneratePdfService.new(invoice:).render_html` returns the
  rendered HTML and is sufficient for unit-testing the templates without
  having to hit the Gotenberg PDF service.
- Stub the Gotenberg HTTP call via `stub_pdf_generation` (already used in
  `spec/services/invoices/generate_pdf_service_spec.rb`) when the full
  `call` path is exercised.
- Use `spec/factories/presentation_breakdowns.rb` (default and
  `:with_composite_presentation_by` trait) to build breakdowns for fees in
  the fixtures.
- The new partial can also be rendered in isolation via
  `SlimHelper.render('templates/invoices/v4/_presentation_breakdowns', context, fees: [...])`
  for focused unit tests independent of the surrounding template.
