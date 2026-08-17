# frozen_string_literal: true

require "rails_helper"

# Tests filter-level cascade for create, update, and destroy operations.
# Each filter operation cascades only that specific filter to child charges
RSpec.describe "Cascade filter updates", :premium do
  include ScenariosHelper

  let(:organization) { create(:organization, webhook_url: nil) }
  let(:customer) { create(:customer, organization:) }

  let(:billable_metric) { create(:billable_metric, organization:, code: "storage") }
  let(:bm_filter) do
    create(:billable_metric_filter, billable_metric:, key: "region", values: %w[us eu asia])
  end

  before { bm_filter }

  # Sets up a parent plan with a charge and two filters, a subscription with
  # a charge override, and returns the key objects for assertions.
  def setup_plan_with_subscription
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

    {parent_plan:, parent_charge:, child_charge:}
  end

  # Broadening a filter's values does not edit it: CreateOrUpdateBatchService pairs the payload with
  # the existing filters by their values, finds no match, and creates a new one while discarding the
  # old. So the code changes too, and the diff sees the old one removed and a new one added — which
  # is why a filter keeping its code always keeps its values, and `unchanged?` need not compare them.
  it "replaces rather than edits a filter when a value is added to it" do
    ctx = setup_plan_with_subscription
    parent_charge = ctx[:parent_charge]
    child_charge = ctx[:child_charge]

    filter_us = parent_charge.filters.find_by(invoice_display_name: "US region")
    old_id = filter_us.id
    old_code = filter_us.code

    update_plan(ctx[:parent_plan], {
      name: "Enterprise", code: "enterprise", interval: "monthly", amount_cents: 0,
      amount_currency: "EUR", pay_in_advance: false, cascade_updates: true,
      charges: [
        {
          id: parent_charge.id,
          billable_metric_id: billable_metric.id,
          charge_model: "standard",
          code: "storage_charge",
          pay_in_advance: false,
          properties: {amount: "0"},
          filters: [
            {invoice_display_name: "US region", properties: {amount: "10"}, values: {region: %w[us eu]}}
          ]
        }
      ]
    })

    replacement = parent_charge.filters.reload.sole
    expect(replacement.id).not_to eq(old_id)
    expect(replacement.code).not_to eq(old_code)
    expect(replacement.to_h).to eq({"region" => %w[us eu]})

    # One filter on the override, not two: the destroy reached the old copy by its code and the
    # create made the new one
    child_filter = child_charge.filters.reload.sole
    expect(child_filter.code).to eq(replacement.code)
    expect(child_filter.to_h).to eq({"region" => %w[us eu]})
  end

  # The negotiated price is lost, because widening replaces the filter rather than editing it and
  # the replacement is created with the plan's price. `filter_customized?` only guards the update
  # path, and a widening never takes it.
  #
  # Pending rather than absent: this is a billing bug — the override starts charging the plan's
  # price with nothing in the logs — and it predates the cascade being keyed by code, so it is not
  # this change's to fix. The fix is letting the plan payload name a filter by its code, which makes
  # widening an update. On the day that lands, this passes and RSpec says so.
  it "keeps a price negotiated on the override when the plan widens a filter" do
    pending "the plan payload cannot name a filter, so widening replaces it instead of editing it"

    ctx = setup_plan_with_subscription
    parent_charge = ctx[:parent_charge]
    child_charge = ctx[:child_charge]
    subscription = organization.subscriptions.find_by(external_id: "sub_enterprise")

    # The customer negotiates the US segment down from 10 to 2
    child_us = child_charge.filters.find_by(invoice_display_name: "US region")
    update_subscription_charge_filter(subscription, "storage_charge", child_us.id, {properties: {amount: "2"}})
    expect(child_us.reload.properties).to eq({"amount" => "2"})

    # The plan widens its US filter to cover EU as well, leaving its own price at 10
    update_plan(ctx[:parent_plan], {
      name: "Enterprise", code: "enterprise", interval: "monthly", amount_cents: 0,
      amount_currency: "EUR", pay_in_advance: false, cascade_updates: true,
      charges: [
        {
          id: parent_charge.id,
          billable_metric_id: billable_metric.id,
          charge_model: "standard",
          code: "storage_charge",
          pay_in_advance: false,
          properties: {amount: "0"},
          filters: [
            {invoice_display_name: "US region", properties: {amount: "10"}, values: {region: %w[us eu]}}
          ]
        }
      ]
    })

    expect(child_charge.filters.reload.sole.properties).to eq({"amount" => "2"})
  end

  # The override is created only after the plan has already widened the filter, so there is nothing
  # on the child to reconcile — it deep-copies whatever the plan holds at that moment. Widening
  # replaces the filter rather than editing it, so what gets copied is the replacement, and the two
  # sides line up on its code.
  context "when the plan widens a filter before any override exists" do
    let(:bm_filter) do
      create(:billable_metric_filter, billable_metric:, key: "region", values: %w[us eu asia apac])
    end

    def plan_payload(values, charge_id: nil)
      charge = {
        billable_metric_id: billable_metric.id,
        charge_model: "standard",
        code: "storage_charge",
        pay_in_advance: false,
        properties: {amount: "0"},
        filters: [{invoice_display_name: "Regions", properties: {amount: "10"}, values: {region: values}}]
      }
      charge[:id] = charge_id if charge_id

      {
        name: "Enterprise", code: "enterprise", interval: "monthly", amount_cents: 0,
        amount_currency: "EUR", pay_in_advance: false, cascade_updates: true, charges: [charge]
      }
    end

    it "gives the override's copy the same code as the plan's filter" do
      # 1. a plan whose charge carries one filter on three values
      create_plan(plan_payload(%w[us eu asia]))
      plan = organization.plans.find_by(code: "enterprise")
      charge = plan.charges.find_by(code: "storage_charge")
      three_value_code = charge.filters.sole.code

      # 2. the plan widens it to four. The filter is replaced rather than edited, so the code changes
      update_plan(plan, plan_payload(%w[us eu asia apac], charge_id: charge.id))
      plan_filter = charge.filters.reload.sole
      expect(plan_filter.code).not_to eq(three_value_code)

      # 3. only now is the charge overridden for a customer
      create_subscription({
        external_customer_id: customer.external_id,
        external_id: "sub_enterprise",
        plan_code: "enterprise"
      })
      subscription = organization.subscriptions.find_by(external_id: "sub_enterprise")
      update_subscription_charge(subscription, "storage_charge", {properties: {amount: "0"}})
      child_charge = subscription.reload.plan.charges.find_by(code: "storage_charge")

      # 4. the copy carries the plan's current code, and the replaced filter was not copied with it
      child_filter = child_charge.filters.sole
      expect(child_filter.code).to eq(plan_filter.code)
      expect(child_filter.to_h["region"]).to match_array(%w[us eu asia apac])
    end
  end

  # A filter created straight on the override derives its code from its own values, and generate_code
  # is deterministic, so the plan derives the very same one when it later prices that segment. The two
  # line up by construction rather than by adoption: the create finds the copy by its code, so nothing
  # is duplicated and the negotiated price stays.
  it "lines up an override-only filter with the plan's when the plan later prices that segment" do
    ctx = setup_plan_with_subscription
    parent_charge = ctx[:parent_charge]
    child_charge = ctx[:child_charge]
    subscription = organization.subscriptions.find_by(external_id: "sub_enterprise")

    # The customer buys a segment the plan does not price, at a negotiated 3
    create_subscription_charge_filter(subscription, "storage_charge", {
      invoice_display_name: "Asia negotiated", properties: {amount: "3"}, values: {region: ["asia"]}
    })

    asia = {"region" => ["asia"]}
    child_asia = child_charge.filters.reload.find { it.to_h == asia }
    expect(parent_charge.filters.reload.map(&:to_h)).not_to include(asia)

    # The plan now prices that same segment, at its own 20
    update_plan(ctx[:parent_plan], {
      name: "Enterprise", code: "enterprise", interval: "monthly", amount_cents: 0,
      amount_currency: "EUR", pay_in_advance: false, cascade_updates: true,
      charges: [
        {
          id: parent_charge.id,
          billable_metric_id: billable_metric.id,
          charge_model: "standard",
          code: "storage_charge",
          pay_in_advance: false,
          properties: {amount: "0"},
          filters: [
            {invoice_display_name: "US region", properties: {amount: "10"}, values: {region: ["us"]}},
            {invoice_display_name: "EU region", properties: {amount: "20"}, values: {region: ["eu"]}},
            {invoice_display_name: "Asia", properties: {amount: "20"}, values: {region: ["asia"]}}
          ]
        }
      ]
    })

    parent_asia = parent_charge.filters.reload.find { it.to_h == asia }
    expect(parent_asia.code).to eq(child_asia.code)

    # One filter on the override, still at the negotiated price
    expect(child_charge.filters.reload.select { it.to_h == asia }).to eq([child_asia])
    expect(child_asia.reload.properties).to eq({"amount" => "3"})
  end

  it "cascades rapid-fire filter updates independently" do
    ctx = setup_plan_with_subscription
    parent_plan = ctx[:parent_plan]
    parent_charge = ctx[:parent_charge]
    child_charge = ctx[:child_charge]
    filter_us = parent_charge.filters.find_by(invoice_display_name: "US region")
    filter_eu = parent_charge.filters.find_by(invoice_display_name: "EU region")
    child_filter_us = child_charge.filters.find_by(invoice_display_name: "US region")
    child_filter_eu = child_charge.filters.find_by(invoice_display_name: "EU region")

    # Queue multiple filter updates without executing jobs
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

    # Each filter update enqueued its own independent CascadeJob
    perform_all_enqueued_jobs

    expect(child_filter_us.reload.properties).to eq({"amount" => "15"})
    expect(child_filter_eu.reload.properties).to eq({"amount" => "25"})
  end

  it "cascades filter creation to child charges" do
    ctx = setup_plan_with_subscription
    parent_plan = ctx[:parent_plan]
    parent_charge = ctx[:parent_charge]
    child_charge = ctx[:child_charge]

    expect(child_charge.filters.count).to eq(2)

    create_plan_charge_filter(parent_plan, parent_charge.code, {
      invoice_display_name: "Asia region",
      properties: {amount: "30"},
      values: {region: ["asia"]},
      cascade_updates: true
    })

    child_charge.reload
    expect(child_charge.filters.count).to eq(3)

    child_filter_asia = child_charge.filters.find_by(invoice_display_name: "Asia region")
    expect(child_filter_asia.properties).to eq({"amount" => "30"})
    expect(child_filter_asia.to_h).to eq({"region" => ["asia"]})
  end

  it "cascades filter deletion to child charges" do
    ctx = setup_plan_with_subscription
    parent_plan = ctx[:parent_plan]
    parent_charge = ctx[:parent_charge]
    child_charge = ctx[:child_charge]
    filter_eu = parent_charge.filters.find_by(invoice_display_name: "EU region")

    expect(child_charge.filters.count).to eq(2)

    delete_plan_charge_filter(parent_plan, parent_charge.code, filter_eu.id, {cascade_updates: true})

    child_charge.reload
    expect(child_charge.filters.count).to eq(1)
    expect(child_charge.filters.first.invoice_display_name).to eq("US region")
  end

  # The copy is found by the code the override inherited. Without one there is nothing to identify
  # it by, and whatever sits on the predicate may be a filter the customer negotiated, so it stays.
  it "leaves a child copy with no code alone when the plan's filter is deleted" do
    ctx = setup_plan_with_subscription
    parent_plan = ctx[:parent_plan]
    parent_charge = ctx[:parent_charge]
    child_charge = ctx[:child_charge]
    filter_eu = parent_charge.filters.find_by(invoice_display_name: "EU region")

    child_copy = child_charge.filters.find_by(invoice_display_name: "EU region")
    child_copy.update!(code: nil)

    delete_plan_charge_filter(parent_plan, parent_charge.code, filter_eu.id, {cascade_updates: true})

    expect(child_copy.reload).not_to be_discarded
    expect(child_charge.filters.reload.count).to eq(2)
  end

  it "does not overwrite a customer-customized filter" do
    ctx = setup_plan_with_subscription
    parent_plan = ctx[:parent_plan]
    parent_charge = ctx[:parent_charge]
    child_charge = ctx[:child_charge]
    filter_us = parent_charge.filters.find_by(invoice_display_name: "US region")
    child_filter_us = child_charge.filters.find_by(invoice_display_name: "US region")

    # Customer customizes the US filter on their subscription
    child_filter_us.update!(properties: {"amount" => "99"})

    # Admin updates the same filter on the parent plan
    update_plan_charge_filter(
      parent_plan, parent_charge.code, filter_us.id,
      {properties: {amount: "15"}, cascade_updates: true}
    )

    # Customer's override is preserved
    expect(child_filter_us.reload.properties).to eq({"amount" => "99"})
  end
end
