# frozen_string_literal: true

# =============================================================================
# Scenario 1: Self-Billed Invoices (v4) — ALL branches inside self_billed.slim
# =============================================================================
#
# Goal: produce invoices that, through `Invoices::GeneratePdfService#template`,
# resolve to "invoices/v4/self_billed" and exercise each of the 5 inner branches
# of `app/views/templates/invoices/v4/self_billed.slim`:
#
#   - if one_off?            -> renders `_one_off`
#   - elsif credit?          -> renders `_credit`
#   - elsif progressive_billing? -> renders `_progressive_billing_details`
#   - elsif subscriptions.count == 1 -> renders `_subscription_details`
#   - else                   -> renders `_subscriptions_summary`
#                              + bottom `_subscription_details` when > 1 sub.
#
# Chain followed in GeneratePdfService#template for every invoice in this file:
#   1. invoice.self_billed?  => TRUE  (we always set self_billed: true)
#   2. version_number        => 4     (default)
#   3. template returned     => "invoices/v4/self_billed"
#
# Service that creates such invoices in production:
#   `Invoices::CreateGeneratingService` sets `self_billed: customer.partner_account?`
#   when the customer's account_type is "partner" AND the organization has the
#   `revenue_share` premium integration enabled.
#
# How to run:
#   bundle exec rails runner db/seeds/scenarios/presentation_breakdowns/01_self_billed.rb
#
# After running, generate HTML for each invoice:
#   inv = Invoice.find_by!(number: "SELF-BILLED-PB-SUB-001") # or another number
#   Invoices::GeneratePdfService.new(invoice: inv).render_html
#
# Numbers created (5):
#   - SELF-BILLED-PB-SUB-001    subscription single-sub  -> _subscription_details
#   - SELF-BILLED-PB-ONEOFF-001 one_off                  -> _one_off
#   - SELF-BILLED-PB-CREDIT-001 credit (wallet)          -> _credit
#   - SELF-BILLED-PB-PROGB-001  progressive_billing      -> _progressive_billing_details
#   - SELF-BILLED-PB-MULTI-001  subscription multi-sub   -> _subscriptions_summary
#                                                          + bottom _subscription_details
# =============================================================================

require "securerandom"

License.instance_variable_set(:@premium, true) unless License.premium?

ActiveRecord::Base.transaction do
  # ===========================================================================
  # Shared resources (org, billing entity, customer, plan, charge, subscription)
  # ===========================================================================
  #
  # Re-uses the existing "Hooli" organization seeded by db/seeds/01_base.rb.
  # The script will raise if Hooli is not present — run base seeds first:
  #   bundle exec rails db:seed
  # ===========================================================================

  organization = Organization.find_by!(name: "Hooli")
  # Ensure required premium integrations are enabled for self_billed + progressive_billing.
  # 01_base.rb already sets PREMIUM_INTEGRATIONS, but keep this idempotent in case it changes.
  organization.update!(
    premium_integrations: (organization.premium_integrations + %w[revenue_share progressive_billing]).uniq
  )

  billing_entity = organization.default_billing_entity

  customer = Customer.find_or_create_by!(
    organization:,
    external_id: "pb-self-billed-customer"
  ) do |c|
    c.billing_entity = billing_entity
    c.name = "Self-Billed Partner Customer"
    c.email = "partner@hooli.com"
    c.country = "FR"
    c.address_line1 = "10 rue du Partenaire"
    c.city = "Paris"
    c.zipcode = "75002"
    c.currency = "EUR"
    c.account_type = "partner"
  end
  customer.update!(account_type: "partner") unless customer.partner_account?

  billable_metric = BillableMetric.find_or_create_by!(organization:, code: "pb_compute") do |bm|
    bm.name = "Compute Usage"
    bm.aggregation_type = "sum_agg"
    bm.field_name = "units"
    bm.recurring = false
  end

  plan = Plan.find_or_create_by!(organization:, code: "pb_self_billed_plan") do |p|
    p.name = "PB Self-Billed Plan"
    p.invoice_display_name = "PB Self-Billed Plan"
    p.interval = "monthly"
    p.pay_in_advance = false
    p.amount_cents = 100_00
    p.amount_currency = "EUR"
  end

  charge = Charge.find_or_create_by!(
    organization:,
    plan:,
    billable_metric:,
    code: "pb_compute_charge"
  ) do |ch|
    ch.charge_model = "standard"
    ch.pay_in_advance = false
    ch.invoice_display_name = "Compute"
    ch.properties = {
      "amount" => "1",
      "presentation_group_keys" => [
        {"value" => "region", "options" => {"display_in_invoice" => true}},
        {"value" => "department", "options" => {"display_in_invoice" => true}}
      ]
    }
  end

  subscription = Subscription.find_or_create_by!(
    organization:,
    customer:,
    external_id: "pb-self-billed-sub"
  ) do |s|
    s.plan = plan
    s.status = :active
    s.started_at = 1.month.ago
    s.activated_at = 1.month.ago
    s.subscription_at = 1.month.ago
    s.billing_time = :calendar
  end

  # ---------------------------------------------------------------------------
  # Second plan + charge + subscription (used by the multi-subscription branch)
  # ---------------------------------------------------------------------------
  plan_b = Plan.find_or_create_by!(organization:, code: "pb_self_billed_plan_b") do |p|
    p.name = "PB Self-Billed Plan B"
    p.invoice_display_name = "PB Self-Billed Plan B"
    p.interval = "monthly"
    p.pay_in_advance = false
    p.amount_cents = 50_00
    p.amount_currency = "EUR"
  end

  charge_b = Charge.find_or_create_by!(
    organization:,
    plan: plan_b,
    billable_metric:,
    code: "pb_compute_charge_b"
  ) do |ch|
    ch.charge_model = "standard"
    ch.pay_in_advance = false
    ch.invoice_display_name = "Storage"
    ch.properties = {
      "amount" => "1",
      "presentation_group_keys" => [
        {"value" => "region", "options" => {"display_in_invoice" => true}},
        {"value" => "department", "options" => {"display_in_invoice" => true}}
      ]
    }
  end

  subscription_b = Subscription.find_or_create_by!(
    organization:,
    customer:,
    external_id: "pb-self-billed-sub-b"
  ) do |s|
    s.plan = plan_b
    s.status = :active
    s.started_at = 1.month.ago
    s.activated_at = 1.month.ago
    s.subscription_at = 1.month.ago
    s.billing_time = :calendar
  end

  fee_properties = {
    "timestamp" => Time.current,
    "from_datetime" => Date.current.beginning_of_month.beginning_of_day,
    "to_datetime" => Date.current.end_of_month.end_of_day,
    "charges_from_datetime" => Date.current.beginning_of_month.beginning_of_day,
    "charges_to_datetime" => Date.current.end_of_month.end_of_day,
    "charges_duration" => 30
  }

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Build an invoice with the right common attributes for self_billed v4.
  build_invoice = lambda do |number:, invoice_type:|
    Invoice.find_or_create_by!(
      organization:,
      customer:,
      number:
    ) do |inv|
      inv.billing_entity = billing_entity
      inv.invoice_type = invoice_type
      inv.currency = "EUR"
      inv.timezone = "UTC"
      inv.status = :finalized
      inv.self_billed = true
      inv.issuing_date = Date.current
      inv.expected_finalization_date = Date.current
      inv.payment_due_date = Date.current
      inv.net_payment_term = 0
      inv.fees_amount_cents = 0
      inv.sub_total_excluding_taxes_amount_cents = 0
      inv.sub_total_including_taxes_amount_cents = 0
      inv.total_amount_cents = 0
      inv.taxes_amount_cents = 0
      inv.taxes_rate = 0
      inv.organization_sequential_id = 0
    end
  end

  # Build a charge fee + its presentation_breakdowns
  build_charge_fee = lambda do |invoice:, sub:, units:, amount_cents:, charge_record: charge, grouped_by: {}, charge_filter: nil, breakdowns: []|
    fee = Fee.find_or_create_by!(
      invoice:,
      subscription: sub,
      charge: charge_record,
      charge_filter:,
      grouped_by:
    ) do |f|
      f.organization = organization
      f.billing_entity = billing_entity
      f.fee_type = :charge
      f.invoiceable_type = "Charge"
      f.invoiceable_id = charge_record.id
      f.amount_cents = amount_cents
      f.precise_amount_cents = amount_cents.to_f
      f.amount_currency = "EUR"
      f.taxes_amount_cents = 0
      f.taxes_precise_amount_cents = 0.0
      f.taxes_rate = 0
      f.units = units
      f.total_aggregated_units = units
      f.events_count = units.to_i
      f.unit_amount_cents = 100
      f.properties = fee_properties
    end

    breakdowns.each do |attrs|
      PresentationBreakdown.find_or_create_by!(
        fee:,
        organization:,
        presentation_by: attrs[:presentation_by]
      ) { |pb| pb.units = attrs[:units] }
    end

    fee
  end

  # Recompute the invoice totals from the actual fees so the totals are coherent.
  refresh_totals = lambda do |invoice|
    total = invoice.fees.sum(:amount_cents)
    invoice.update!(
      fees_amount_cents: total,
      sub_total_excluding_taxes_amount_cents: total,
      sub_total_including_taxes_amount_cents: total,
      total_amount_cents: total
    )
  end

  # ===========================================================================
  # Branch A: subscriptions.count == 1  ->  _subscription_details
  # ===========================================================================
  #
  # invoice_type: :subscription, attaches one InvoiceSubscription pointing to
  # the shared `subscription`. Three charge fees exercise the 3 markdown
  # scenarios (grouped_by empty / present / charge_filter present).

  sub_invoice = build_invoice.call(
    number: "SELF-BILLED-PB-SUB-001",
    invoice_type: :subscription
  )

  # NOTE: recurring=false avoids index_uniq_invoice_subscriptions_on_charges_from_to_datetime
  # which would conflict when re-running this script with the same boundaries.
  InvoiceSubscription.find_or_create_by!(invoice: sub_invoice, subscription:) do |is_|
    is_.organization = organization
    is_.recurring = false
    is_.timestamp = Date.current.beginning_of_month
    is_.from_datetime = Date.current.beginning_of_month.beginning_of_day
    is_.to_datetime = Date.current.end_of_month.end_of_day
    is_.charges_from_datetime = (Date.current - 1.month).beginning_of_month.beginning_of_day
    is_.charges_to_datetime = Date.current.end_of_month.end_of_day
  end

  # Fee A — grouped_by empty
  build_charge_fee.call(
    invoice: sub_invoice, sub: subscription, units: 110, amount_cents: 110_00,
    grouped_by: {},
    breakdowns: [
      {presentation_by: {"region" => "eu", "department" => "engineering"}, units: 40},
      {presentation_by: {"region" => "us", "department" => "engineering"}, units: 35},
      {presentation_by: {"region" => "us", "department" => "sales"}, units: 25},
      {presentation_by: {"region" => "us", "department" => nil}, units: 10}
    ]
  )

  # Fee B — grouped_by present
  build_charge_fee.call(
    invoice: sub_invoice, sub: subscription, units: 65, amount_cents: 65_00,
    grouped_by: {"region" => "eu"},
    breakdowns: [
      {presentation_by: {"region" => "eu", "department" => "engineering"}, units: 40},
      {presentation_by: {"region" => "eu", "department" => "sales"}, units: 20},
      {presentation_by: {"region" => "eu", "department" => nil}, units: 5}
    ]
  )

  # Fee C — charge_filter_id present
  charge_filter = ChargeFilter.find_or_create_by!(
    organization:,
    charge:,
    invoice_display_name: "EU Premium"
  ) { |cf| cf.properties = {"amount" => "1"} }

  build_charge_fee.call(
    invoice: sub_invoice, sub: subscription, units: 50, amount_cents: 50_00,
    grouped_by: {}, charge_filter:,
    breakdowns: [
      {presentation_by: {"region" => "eu", "department" => "engineering"}, units: 30},
      {presentation_by: {"region" => "eu", "department" => "sales"}, units: 15},
      {presentation_by: {"region" => "eu", "department" => nil}, units: 5}
    ]
  )

  refresh_totals.call(sub_invoice)

  # ===========================================================================
  # Branch B: one_off?  ->  _one_off
  # ===========================================================================
  #
  # invoice_type: :one_off. _one_off.slim iterates `fees.ordered_by_period` and
  # expects add_on fees. We attach a single add_on fee.

  one_off_invoice = build_invoice.call(
    number: "SELF-BILLED-PB-ONEOFF-001",
    invoice_type: :one_off
  )

  add_on = AddOn.find_or_create_by!(organization:, code: "pb_self_billed_addon") do |a|
    a.name = "PB Setup Fee"
    a.invoice_display_name = "PB Setup Fee"
    a.amount_cents = 200_00
    a.amount_currency = "EUR"
    a.description = "One-off setup fee for the self-billed scenario"
  end

  Fee.find_or_create_by!(
    invoice: one_off_invoice,
    add_on:,
    fee_type: :add_on
  ) do |f|
    f.organization = organization
    f.billing_entity = billing_entity
    f.subscription = nil
    f.invoiceable_type = "AddOn"
    f.invoiceable_id = add_on.id
    f.amount_cents = 200_00
    f.precise_amount_cents = 200_00.0
    f.amount_currency = "EUR"
    f.taxes_amount_cents = 0
    f.taxes_precise_amount_cents = 0.0
    f.taxes_rate = 0
    f.units = 1
    f.unit_amount_cents = 200_00
    f.invoice_display_name = "PB Setup Fee"
    f.properties = {
      "from_datetime" => Date.current.beginning_of_day,
      "to_datetime" => Date.current.end_of_day
    }
  end

  refresh_totals.call(one_off_invoice)

  # ===========================================================================
  # Branch C: credit?  ->  _credit
  # ===========================================================================
  #
  # invoice_type: :credit. _credit.slim reads `fees.first.invoiceable` and
  # expects a WalletTransaction with `credit_amount`, `wallet.rate_amount` and
  # `wallet.name`.

  credit_invoice = build_invoice.call(
    number: "SELF-BILLED-PB-CREDIT-001",
    invoice_type: :credit
  )

  wallet = Wallet.find_or_create_by!(organization:, customer:, name: "PB Self-Billed Wallet") do |w|
    w.status = "active"
    w.rate_amount = "1.0"
    w.currency = "EUR"
    w.credits_balance = 0
    w.balance_cents = 0
    w.consumed_credits = 0
    w.invoice_requires_successful_payment = false
    w.traceable = true
  end

  wallet_transaction = WalletTransaction.find_or_create_by!(
    organization:,
    wallet:,
    name: "Top-up — Self-billed credit"
  ) do |wt|
    wt.transaction_type = :inbound
    wt.transaction_status = :purchased
    wt.status = :settled
    wt.amount = "50.0"
    wt.credit_amount = "50.0"
    wt.settled_at = Time.current
    wt.remaining_amount_cents = 50_00
    wt.invoice_requires_successful_payment = false
  end

  Fee.find_or_create_by!(
    invoice: credit_invoice,
    fee_type: :credit,
    invoiceable_type: "WalletTransaction",
    invoiceable_id: wallet_transaction.id
  ) do |f|
    f.organization = organization
    f.billing_entity = billing_entity
    f.subscription = nil
    f.amount_cents = 50_00
    f.precise_amount_cents = 50_00.0
    f.amount_currency = "EUR"
    f.taxes_amount_cents = 0
    f.taxes_precise_amount_cents = 0.0
    f.taxes_rate = 0
    f.units = 1
    f.unit_amount_cents = 50_00
    f.invoice_display_name = "PB Credit"
    f.properties = {}
  end

  refresh_totals.call(credit_invoice)

  # ===========================================================================
  # Branch D: progressive_billing?  ->  _progressive_billing_details
  # ===========================================================================
  #
  # invoice_type: :progressive_billing. The template reads:
  #   - subscriptions.first (we need an InvoiceSubscription with boundaries)
  #   - subscription_fees(subscription.id).charge (we attach charge fees)
  # We also attach an AppliedUsageThreshold because v4.slim/self_billed.slim
  # render `reached_usage_threshold` text when progressive_billing? is true.

  pb_invoice = build_invoice.call(
    number: "SELF-BILLED-PB-PROGB-001",
    invoice_type: :progressive_billing
  )

  InvoiceSubscription.find_or_create_by!(invoice: pb_invoice, subscription:) do |is_|
    is_.organization = organization
    is_.recurring = false
    is_.timestamp = Date.current.beginning_of_month
    is_.from_datetime = Date.current.beginning_of_month.beginning_of_day
    is_.to_datetime = Date.current.end_of_month.end_of_day
    is_.charges_from_datetime = Date.current.beginning_of_month.beginning_of_day
    is_.charges_to_datetime = Date.current.end_of_month.end_of_day
  end

  usage_threshold = UsageThreshold.find_or_create_by!(plan:, threshold_display_name: "PB First Threshold") do |ut|
    ut.organization = organization
    ut.amount_cents = 100_00
    ut.recurring = false
  end

  AppliedUsageThreshold.find_or_create_by!(invoice: pb_invoice, usage_threshold:) do |aut|
    aut.organization = organization
    aut.lifetime_usage_amount_cents = 120_00
  end

  # Charge fee with breakdowns (progressive_billing template renders charge fees)
  build_charge_fee.call(
    invoice: pb_invoice, sub: subscription, units: 90, amount_cents: 90_00,
    grouped_by: {},
    breakdowns: [
      {presentation_by: {"region" => "eu", "department" => "engineering"}, units: 50},
      {presentation_by: {"region" => "us", "department" => "sales"}, units: 30},
      {presentation_by: {"region" => "us", "department" => nil}, units: 10}
    ]
  )

  refresh_totals.call(pb_invoice)

  # ===========================================================================
  # Branch E: subscriptions.count > 1  ->  _subscriptions_summary  (inline)
  #                                      + bottom _subscription_details
  # ===========================================================================
  #
  # invoice_type: :subscription, attaches TWO InvoiceSubscriptions (each
  # pointing at a different subscription with its own plan/charge). Inside
  # self_billed.slim:
  #   - first the inline branch `else` renders `_subscriptions_summary`
  #     (see self_billed.slim line ~452)
  #   - then the bottom block `if subscriptions.count > 1` re-renders
  #     `_subscription_details` for each subscription
  #     (see self_billed.slim lines ~468-469)
  #
  # Each subscription gets one charge fee with presentation_breakdowns so the
  # partial can be exercised on both subscriptions.

  multi_invoice = build_invoice.call(
    number: "SELF-BILLED-PB-MULTI-001",
    invoice_type: :subscription
  )

  # InvoiceSubscription #1 - subscription "A" (uses `charge`)
  InvoiceSubscription.find_or_create_by!(invoice: multi_invoice, subscription:) do |is_|
    is_.organization = organization
    is_.recurring = false
    is_.timestamp = Date.current.beginning_of_month
    is_.from_datetime = Date.current.beginning_of_month.beginning_of_day
    is_.to_datetime = Date.current.end_of_month.end_of_day
    is_.charges_from_datetime = (Date.current - 1.month).beginning_of_month.beginning_of_day
    is_.charges_to_datetime = Date.current.end_of_month.end_of_day
  end

  # InvoiceSubscription #2 - subscription "B" (uses `charge_b`)
  InvoiceSubscription.find_or_create_by!(invoice: multi_invoice, subscription: subscription_b) do |is_|
    is_.organization = organization
    is_.recurring = false
    is_.timestamp = Date.current.beginning_of_month
    is_.from_datetime = Date.current.beginning_of_month.beginning_of_day
    is_.to_datetime = Date.current.end_of_month.end_of_day
    is_.charges_from_datetime = (Date.current - 1.month).beginning_of_month.beginning_of_day
    is_.charges_to_datetime = Date.current.end_of_month.end_of_day
  end

  # Charge fee for subscription A on `charge` (grouped_by empty + nil breakdown row)
  build_charge_fee.call(
    invoice: multi_invoice, sub: subscription, charge_record: charge,
    units: 80, amount_cents: 80_00,
    grouped_by: {},
    breakdowns: [
      {presentation_by: {"region" => "eu", "department" => "engineering"}, units: 45},
      {presentation_by: {"region" => "us", "department" => "sales"}, units: 30},
      {presentation_by: {"region" => "us", "department" => nil}, units: 5}
    ]
  )

  # Charge fee for subscription B on `charge_b` (grouped_by present)
  build_charge_fee.call(
    invoice: multi_invoice, sub: subscription_b, charge_record: charge_b,
    units: 40, amount_cents: 40_00,
    grouped_by: {"region" => "eu"},
    breakdowns: [
      {presentation_by: {"region" => "eu", "department" => "engineering"}, units: 25},
      {presentation_by: {"region" => "eu", "department" => "sales"}, units: 10},
      {presentation_by: {"region" => "eu", "department" => nil}, units: 5}
    ]
  )

  refresh_totals.call(multi_invoice)

  # ===========================================================================
  # Summary
  # ===========================================================================

  Rails.logger.debug "✅ Self-billed scenarios ready (template: invoices/v4/self_billed)"
  Rails.logger.debug ""
  Rails.logger.debug "  [A] subscriptions.count == 1  -> _subscription_details"
  Rails.logger.debug "      Invoice number: #{sub_invoice.number}  id=#{sub_invoice.id}"
  Rails.logger.debug ""
  Rails.logger.debug "  [B] one_off?                  -> _one_off"
  Rails.logger.debug "      Invoice number: #{one_off_invoice.number}  id=#{one_off_invoice.id}"
  Rails.logger.debug ""
  Rails.logger.debug "  [C] credit?                   -> _credit"
  Rails.logger.debug "      Invoice number: #{credit_invoice.number}  id=#{credit_invoice.id}"
  Rails.logger.debug ""
  Rails.logger.debug "  [D] progressive_billing?      -> _progressive_billing_details"
  Rails.logger.debug "      Invoice number: #{pb_invoice.number}  id=#{pb_invoice.id}"
  Rails.logger.debug ""
  Rails.logger.debug "  [E] subscriptions.count > 1   -> _subscriptions_summary + bottom _subscription_details"
  Rails.logger.debug "      Invoice number: #{multi_invoice.number}  id=#{multi_invoice.id}"
  Rails.logger.debug ""
  Rails.logger.debug "Generate HTML for any of them:"
  Rails.logger.debug "  Invoices::GeneratePdfService.new(invoice: Invoice.find_by!(number: 'SELF-BILLED-PB-SUB-001')).render_html"
end
