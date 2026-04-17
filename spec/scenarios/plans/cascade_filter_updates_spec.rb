# frozen_string_literal: true

require "rails_helper"

# Reproduces the real-world scenario where a customer rapidly updates multiple
# charge filters via the API (e.g. 160+ PUT requests in quick succession).
# Each filter update cascades only that specific filter to child charges,
# so there's no ordering issue — each cascade is independent.
RSpec.describe "Cascade filter updates", :premium do
  include ScenariosHelper

  let(:organization) { create(:organization, webhook_url: nil) }
  let(:customer) { create(:customer, organization:) }

  let(:billable_metric) { create(:billable_metric, organization:, code: "storage") }
  let(:bm_filter) do
    create(:billable_metric_filter, billable_metric:, key: "region", values: %w[us eu asia])
  end

  before { bm_filter }

  it "applies all filter changes when multiple updates are fired in quick succession" do
    create_plan({
      name: "Enterprise",
      code: "enterprise",
      interval: "monthly",
      amount_cents: 0,
      amount_currency: "EUR",
      pay_in_advance: false,
      charges: [
        {
          billable_metric_id: billable_metric.id,
          charge_model: "standard",
          code: "storage_charge",
          pay_in_advance: false,
          properties: {amount: "0"},
          filters: [
            {
              invoice_display_name: "US region",
              properties: {amount: "10"},
              values: {region: ["us"]}
            },
            {
              invoice_display_name: "EU region",
              properties: {amount: "20"},
              values: {region: ["eu"]}
            }
          ]
        }
      ]
    })

    parent_plan = organization.plans.find_by(code: "enterprise")
    parent_charge = parent_plan.charges.first
    filter_us = parent_charge.filters.find_by(invoice_display_name: "US region")
    filter_eu = parent_charge.filters.find_by(invoice_display_name: "EU region")

    # Customer subscribes and overrides a charge → creates child plan + child charge
    create_subscription({
      external_customer_id: customer.external_id,
      external_id: "sub_enterprise",
      plan_code: "enterprise"
    })

    subscription = organization.subscriptions.find_by(external_id: "sub_enterprise")

    update_subscription_charge(subscription, "storage_charge", {
      invoice_display_name: "My storage",
      properties: {amount: "0"}
    })

    subscription.reload
    child_charge = subscription.plan.charges.find_by(code: "storage_charge")
    child_filter_us = child_charge.filters.find_by(invoice_display_name: "US region")
    child_filter_eu = child_charge.filters.find_by(invoice_display_name: "EU region")

    expect(child_filter_us.properties).to eq({"amount" => "10"})
    expect(child_filter_eu.properties).to eq({"amount" => "20"})

    # Rapid-fire filter updates — queue cascade jobs without executing them
    update_plan_charge_filter(
      parent_plan, parent_charge.code, filter_us.id,
      {properties: {amount: "15"}, cascade_updates: true},
      perform_jobs: false
    )

    update_plan_charge_filter(
      parent_plan, parent_charge.code, filter_eu.id,
      {properties: {amount: "25"}, cascade_updates: true},
      perform_jobs: false
    )

    # Child is unchanged before jobs run
    expect(child_filter_us.reload.properties).to eq({"amount" => "10"})
    expect(child_filter_eu.reload.properties).to eq({"amount" => "20"})

    # Each filter update enqueued its own independent CascadeJob.
    # No ordering issue — they each update only their own filter on children.
    perform_all_enqueued_jobs

    expect(child_filter_us.reload.properties).to eq({"amount" => "15"})
    expect(child_filter_eu.reload.properties).to eq({"amount" => "25"})
  end
end
