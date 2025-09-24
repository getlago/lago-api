# frozen_string_literal: true

# NOTE: If hooli is not found, run 01_base.rb first
organization = Organization.find_by!(name: "Hooli")
sum_bm = BillableMetric.find_by!(organization:, code: "sum_bm")
count_bm = BillableMetric.find_by!(organization:, code: "count_bm")

# == Standard Plan

unless Plan.exists?(organization:, code: "standard_plan")
  Plans::CreateService.call!(
    organization_id: organization.id,
    name: "Standard Plan",
    code: "standard_plan",
    interval: "monthly",
    pay_in_advance: true,
    amount_cents: 19_99,
    amount_currency: "EUR",
    tax_codes: ["lago_eu_fr_standard"],
    charges: [
      {
        billable_metric_id: sum_bm.id,
        charge_model: "standard",
        amount_currency: "EUR",
        pay_in_advance: false,
        properties: {
          amount: 100.to_s
        }
      },
      {
        billable_metric_id: count_bm.id,
        charge_model: "standard",
        amount_currency: "EUR",
        pay_in_advance: false,
        properties: {
          amount: 499.to_s
        }
      }
    ]
  )
end

# == Pay in Advance Plan

unless Plan.exists?(organization:, code: "premium_plan")
  Plans::CreateService.call!(
    organization_id: organization.id,
    name: "Premium Plan",
    code: "premium_plan",
    interval: "monthly",
    pay_in_advance: true,
    amount_cents: 100_00,
    amount_currency: "EUR",
    tax_codes: ["lago_eu_fr_standard"],
    charges: [
      {
        billable_metric_id: sum_bm.id,
        charge_model: "standard",
        amount_currency: "EUR",
        pay_in_advance: false,
        properties: {
          amount: 30.to_s
        }
      },
      {
        billable_metric_id: count_bm.id,
        charge_model: "standard",
        amount_currency: "EUR",
        pay_in_advance: false,
        properties: {
          amount: 399.to_s
        }
      }
    ]
  )
end
