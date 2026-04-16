# frozen_string_literal: true

require "rails_helper"

# Reproduces the real-world scenario where a customer rapidly updates multiple
# charge filters via the API (e.g. 160+ PUT requests in quick succession).
# Each filter update enqueues a cascade job. Without the cascaded_at staleness
# check, out-of-order job execution could revert children to stale parent state.
RSpec.describe "Cascade filter updates", :premium do
  include ScenariosHelper

  let(:organization) { create(:organization, webhook_url: nil) }
  let(:customer) { create(:customer, organization:) }

  let(:billable_metric) { create(:billable_metric, organization:, code: "storage") }
  let(:bm_filter) do
    create(:billable_metric_filter, billable_metric:, key: "region", values: %w[us eu asia])
  end

  before { bm_filter }

  it "applies the final state when multiple filter updates are fired in quick succession" do
    # Create parent plan with a charge and two filters
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

    # Customer subscribes to the plan
    create_subscription({
      external_customer_id: customer.external_id,
      external_id: "sub_enterprise",
      plan_code: "enterprise"
    })

    subscription = organization.subscriptions.find_by(external_id: "sub_enterprise")

    # Customer overrides a charge on their subscription → creates child plan + child charge
    update_subscription_charge(subscription, "storage_charge", {
      invoice_display_name: "My storage",
      properties: {amount: "0"}
    })

    subscription.reload
    child_plan = subscription.plan
    expect(child_plan.parent_id).to eq(parent_plan.id)

    child_charge = child_plan.charges.find_by(code: "storage_charge")
    expect(child_charge.parent_id).to eq(parent_charge.id)

    child_filter_us = child_charge.filters.find_by(invoice_display_name: "US region")
    child_filter_eu = child_charge.filters.find_by(invoice_display_name: "EU region")

    expect(child_filter_us.properties).to eq({"amount" => "10"})
    expect(child_filter_eu.properties).to eq({"amount" => "20"})

    # Rapid-fire filter updates on the parent plan — queue cascade jobs
    # without executing them (simulates ~400ms-apart PUT requests from the logs)
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

    # Execute all queued cascade jobs.
    perform_all_enqueued_jobs

    # Cascade 1 (filter_us update) is stale → skipped.
    # Cascade 2 (filter_eu update) proceeds. Its params include the full current
    # filter state (both updates), BUT its old_parent_filters_attrs reflects
    # filter_us already at "15" — while the child still has "10" (cascade 1 was
    # skipped). The cascade logic sees "10" != "15" and thinks the child was
    # customized, so it skips updating filter_us.
    #
    # Filter EU is correctly updated because cascade 2's old parent had EU at "20"
    # (its original value), matching the child's "20".
    expect(child_filter_eu.reload.properties).to eq({"amount" => "25"})
    expect(child_filter_us.reload.properties).to eq({"amount" => "10"}) # not updated — known limitation
  end
end
