# frozen_string_literal: true

organization = Organization.find_by!(name: "Hooli")
billing_entity = organization.default_billing_entity || organization.billing_entities.first!
suffix = Time.current.strftime("%Y%m%d%H%M%S")
period_start = Time.zone.parse("2026-01-01 00:00:00")
period_end = Time.zone.parse("2026-01-31 23:59:59.999")

customer = Customer.create!(
  organization:,
  billing_entity:,
  external_id: "bil-170-customer-#{suffix}",
  name: "BIL-170 Regeneration #{suffix}",
  currency: "EUR",
  timezone: "UTC",
  invoice_grace_period: 0,
  net_payment_term: 0
)

plan = Plan.create!(
  organization:,
  name: "BIL-170 Plan #{suffix}",
  code: "bil_170_plan_#{suffix}",
  interval: :monthly,
  amount_cents: 245,
  amount_currency: "EUR",
  pay_in_advance: true
)

subscription = Subscription.create!(
  organization:,
  customer:,
  billing_entity:,
  plan:,
  external_id: "bil-170-subscription-#{suffix}",
  status: :active,
  billing_time: :calendar,
  subscription_at: period_start,
  started_at: period_start
)

billable_metric = BillableMetric.create!(
  organization:,
  name: "BIL-170 Active files #{suffix}",
  code: "bil_170_active_files_#{suffix}",
  aggregation_type: :count_agg,
  recurring: false
)

discarded_charge_parent = Charge.create!(
  organization:,
  plan:,
  billable_metric:,
  code: "bil_170_parent_#{suffix}",
  charge_model: :standard,
  properties: {amount: "0"},
  invoice_display_name: "BIL-170 Parent"
)

discarded_charge = Charge.create!(
  organization:,
  plan:,
  billable_metric:,
  parent: discarded_charge_parent,
  code: "client_files_count_2_#{suffix}",
  charge_model: :graduated,
  properties: {
    graduated_ranges: [
      {from_value: 0, to_value: 1, flat_amount: "0", per_unit_amount: "0"},
      {from_value: 2, to_value: nil, flat_amount: "0", per_unit_amount: "2.37"}
    ]
  },
  invoice_display_name: "Active files",
  pay_in_advance: false,
  min_amount_cents: 0,
  invoiceable: true
)
discarded_charge.discard!

active_filtered_charge = Charge.create!(
  organization:,
  plan:,
  billable_metric:,
  code: "bil_170_filtered_charge_#{suffix}",
  charge_model: :standard,
  properties: {amount: "4.20"},
  invoice_display_name: "Active files filtered",
  pay_in_advance: false,
  min_amount_cents: 0,
  invoiceable: true
)

metric_filter = BillableMetricFilter.create!(
  organization:,
  billable_metric:,
  key: "region",
  values: ["eu", "us"]
)

discarded_charge_filter = ChargeFilter.create!(
  organization:,
  charge: active_filtered_charge,
  invoice_display_name: "EU files",
  properties: {amount: "4.20"}
)

ChargeFilterValue.create!(
  organization:,
  charge_filter: discarded_charge_filter,
  billable_metric_filter: metric_filter,
  values: ["eu"]
)

discarded_charge_filter.assign_code!
discarded_charge_filter.discard!

invoice = Invoice.create!(
  organization:,
  billing_entity:,
  customer:,
  invoice_type: :subscription,
  currency: "EUR",
  timezone: "UTC",
  status: :generating,
  issuing_date: period_start.to_date,
  expected_finalization_date: period_start.to_date,
  payment_due_date: period_start.to_date,
  net_payment_term: 0,
  fees_amount_cents: 245,
  sub_total_excluding_taxes_amount_cents: 245,
  sub_total_including_taxes_amount_cents: 245,
  total_amount_cents: 245,
  taxes_amount_cents: 0,
  coupons_amount_cents: 0,
  credit_notes_amount_cents: 0,
  prepaid_credit_amount_cents: 0,
  payment_status: :pending,
  voided_at: nil,
  voided_invoice_id: nil
)

invoice_subscription = InvoiceSubscription.create!(
  organization:,
  invoice:,
  subscription:,
  timestamp: period_start + 1.minute,
  from_datetime: period_start,
  to_datetime: period_end,
  charges_from_datetime: period_start + 1.minute,
  charges_to_datetime: period_start + 1.minute,
  fixed_charges_from_datetime: period_start + 1.minute,
  fixed_charges_to_datetime: period_start + 1.minute,
  recurring: true,
  invoicing_reason: :subscription_periodic
)

subscription_fee = Fee.create!(
  organization:,
  billing_entity:,
  invoice:,
  subscription:,
  invoiceable: subscription,
  fee_type: :subscription,
  payment_status: :pending,
  amount_currency: "EUR",
  amount_cents: 245,
  precise_amount_cents: 245.to_d,
  taxes_amount_cents: 0,
  taxes_precise_amount_cents: 0.to_d,
  taxes_base_rate: 1,
  taxes_rate: 0,
  units: 1,
  unit_amount_cents: 245,
  precise_unit_amount: 2.45,
  precise_coupons_amount_cents: 0.to_d,
  precise_credit_notes_amount_cents: 0.to_d,
  amount_details: {plan_amount_cents: 245},
  grouped_by: {},
  properties: {
    timestamp: invoice_subscription.timestamp,
    from_datetime: invoice_subscription.from_datetime,
    to_datetime: invoice_subscription.to_datetime,
    charges_duration: 31,
    charges_from_datetime: invoice_subscription.charges_from_datetime,
    charges_to_datetime: invoice_subscription.charges_to_datetime,
    fixed_charges_duration: 31,
    fixed_charges_from_datetime: invoice_subscription.fixed_charges_from_datetime,
    fixed_charges_to_datetime: invoice_subscription.fixed_charges_to_datetime
  }
)

Invoices::FinalizeService.call!(invoice:)
invoice.update!(voided_at: nil, voided_invoice_id: nil)

# rubocop:disable Rails/Output
puts <<~OUTPUT
  Created BIL-170 regeneration data in Hooli.

  Customer: #{customer.id} (external_id: #{customer.external_id})
  Plan: #{plan.id} (code: #{plan.code})
  Subscription: #{subscription.id} (external_id: #{subscription.external_id})
  Finalized invoice: #{invoice.id} (number: #{invoice.number})
  Subscription fee: #{subscription_fee.id}

  Discarded charge target:
  Charge: #{discarded_charge.id} (code: #{discarded_charge.code}, deleted_at: #{discarded_charge.deleted_at})

  Discarded charge filter target:
  Active charge: #{active_filtered_charge.id} (code: #{active_filtered_charge.code})
  Charge filter: #{discarded_charge_filter.id} (code: #{discarded_charge_filter.code}, deleted_at: #{discarded_charge_filter.deleted_at})

  GraphQL variables for the discarded charge case:
  {
    "voidedInvoiceId": "#{invoice.id}",
    "fees": [
      {"id": "#{subscription_fee.id}", "subscriptionId": "#{subscription.id}", "units": 1},
      {"chargeId": "#{discarded_charge.id}", "subscriptionId": "#{subscription.id}", "units": 2}
    ]
  }

  GraphQL variables for the discarded charge filter case:
  {
    "voidedInvoiceId": "#{invoice.id}",
    "fees": [
      {"id": "#{subscription_fee.id}", "subscriptionId": "#{subscription.id}", "units": 1},
      {"chargeId": "#{active_filtered_charge.id}", "chargeFilterId": "#{discarded_charge_filter.id}", "subscriptionId": "#{subscription.id}", "units": 2}
    ]
  }
OUTPUT
# rubocop:enable Rails/Output
