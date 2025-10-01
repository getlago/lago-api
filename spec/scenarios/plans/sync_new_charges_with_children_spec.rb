# frozen_string_literal: true

require "rails_helper"

describe "Sync New Charges With Children Scenario" do
  let(:organization) { create(:organization, webhook_url: nil) }

  around { |test| lago_premium!(&test) }

  it "syncs new charges to child plans and fixes parent_ids after plan updates" do
    # Step 1: Create 20 different billable metrics
    billable_metrics = []
    20.times do |i|
      aggregation_types = %w[count_agg sum_agg latest_agg max_agg unique_count_agg]
      aggregation_type = aggregation_types[i % aggregation_types.length]

      billable_metrics << create(
        :billable_metric,
        organization:,
        name: "Metric #{i + 1}",
        code: "metric_#{i + 1}",
        aggregation_type:,
        field_name: (aggregation_type == "count_agg") ? nil : "field_#{i + 1}"
      )
    end

    # Step 2: Create a plan with 20 charges (one for each billable metric)
    plan_charges = billable_metrics.map.with_index do |bm, i|
      {
        billable_metric_id: bm.id,
        charge_model: "standard",
        invoice_display_name: "Charge #{i + 1}",
        properties: {amount: (100 + i * 10).to_s}
      }
    end

    create_plan(
      {
        name: "Parent Plan",
        code: "parent_plan",
        interval: "monthly",
        amount_cents: 10_000,
        amount_currency: "EUR",
        pay_in_advance: false,
        charges: plan_charges
      }
    )

    parent_plan = organization.plans.find_by(code: "parent_plan")
    expect(parent_plan.charges.count).to eq(20)

    # Step 3: Create 10 customers with subscriptions
    customers = []
    child_plans = []

    # 5 customers with insignificant overrides (display names only)
    5.times do |i|
      customer = create(:customer, organization:, external_id: "customer_#{i + 1}")
      customers << customer

      # Override only display names for some charges
      charge_overrides = parent_plan.charges.first(3).map do |charge|
        {
          id: charge.id,
          invoice_display_name: "Custom Display #{i + 1} - #{charge.invoice_display_name}"
        }
      end

      create_subscription(
        {
          external_customer_id: customer.external_id,
          external_id: "sub_#{i + 1}",
          plan_code: parent_plan.code,
          plan_overrides: {
            charges: charge_overrides
          }
        }
      )

      child_plans << customer.subscriptions.first.plan
    end

    # 5 customers with different prices
    5.times do |i|
      customer = create(:customer, organization:, external_id: "customer_#{i + 6}")
      customers << customer

      # Override prices for some charges
      charge_overrides = parent_plan.charges.first(2).map do |charge|
        {
          id: charge.id,
          properties: {amount: (200 + i * 50).to_s}
        }
      end

      create_subscription(
        {
          external_customer_id: customer.external_id,
          external_id: "sub_#{i + 6}",
          plan_code: parent_plan.code,
          plan_overrides: {
            charges: charge_overrides
          }
        }
      )

      child_plans << customer.subscriptions.first.plan
    end

    expect(child_plans.count).to eq(10)
    expect(child_plans.all? { |plan| plan.parent_id == parent_plan.id }).to be true

    # Step 4: Create new billable metrics for plan updates
    new_billable_metric_1 = create(
      :billable_metric,
      organization:,
      name: "New Metric 1",
      code: "new_metric_1",
      aggregation_type: "sum_agg",
      field_name: "new_field_1"
    )

    new_billable_metric_2 = create(
      :billable_metric,
      organization:,
      name: "New Metric 2",
      code: "new_metric_2",
      aggregation_type: "count_agg"
    )

    # Step 5: Update plan with full payload + one new charge (cascade: false)
    updated_charges_params = parent_plan.charges.map do |charge|
      {
        id: charge.id,
        billable_metric_id: charge.billable_metric_id,
        charge_model: charge.charge_model,
        invoice_display_name: charge.invoice_display_name,
        properties: charge.properties
      }
    end

    # Add the new charge
    updated_charges_params << {
      billable_metric_id: new_billable_metric_1.id,
      charge_model: "standard",
      invoice_display_name: "New Charge 1",
      properties: {amount: "500"}
    }

    update_plan(
      parent_plan,
      {
        name: "Parent Plan",
        code: "parent_plan",
        interval: "monthly",
        amount_cents: 10_000,
        amount_currency: "EUR",
        pay_in_advance: false,
        cascade_updates: false,
        charges: updated_charges_params
      }
    )

    parent_plan.reload
    expect(parent_plan.charges.count).to eq(21)

    # Step 6: Update plan again with new charge (without charge IDs, cascade: false)
    # This will delete old charges and create new ones
    final_charges = parent_plan.charges.map do |charge|
      {
        billable_metric_id: charge.billable_metric_id,
        charge_model: charge.charge_model,
        invoice_display_name: charge.invoice_display_name,
        properties: charge.properties
      }
    end

    # Add the second new charge
    final_charges << {
      billable_metric_id: new_billable_metric_2.id,
      charge_model: "standard",
      invoice_display_name: "New Charge 2",
      properties: {amount: "600"}
    }

    update_plan(
      parent_plan,
      {
        name: "Parent Plan",
        code: "parent_plan",
        interval: "monthly",
        amount_cents: 10_000,
        amount_currency: "EUR",
        pay_in_advance: false,
        cascade_updates: false,
        charges: final_charges
      }
    )

    parent_plan.reload
    expect(parent_plan.charges.count).to eq(22)

    # At this point, child plan charges should have broken parent_ids
    # because the original parent charges were deleted
    child_plans.each do |child_plan|
      child_plan.charges.each do |charge|
        # The parent charge should be deleted (soft deleted)
        expect(Charge.with_discarded.find(charge.parent_id).deleted_at).to be_present
      end
    end

    # Step 7: Run SyncNewChargesWithChildren service and execute all jobs
    Plans::SyncNewChargesWithChildrenService.call(plan: parent_plan)

    # Execute all enqueued jobs
    perform_all_enqueued_jobs

    # Step 8: Verify results
    child_plans.each do |child_plan|
      child_plan.reload

      # Should have only 2 new charges added (the ones from the plan updates)
      new_charges = child_plan.charges.where(
        billable_metric_id: [new_billable_metric_1.id, new_billable_metric_2.id]
      )
      expect(new_charges.count).to eq(2)

      # Verify the new charges have correct properties
      new_charge_1 = new_charges.find_by(billable_metric_id: new_billable_metric_1.id)
      expect(new_charge_1).to have_attributes(
        invoice_display_name: "New Charge 1",
        properties: {"amount" => "500"}
      )

      new_charge_2 = new_charges.find_by(billable_metric_id: new_billable_metric_2.id)
      expect(new_charge_2).to have_attributes(
        invoice_display_name: "New Charge 2",
        properties: {"amount" => "600"}
      )

      # Verify that existing charges have correct parent_ids
      # (they should be linked to the current parent plan charges with same billable_metric)
      existing_charges = child_plan.charges.where.not(
        billable_metric_id: [new_billable_metric_1.id, new_billable_metric_2.id]
      )

      existing_charges.each do |child_charge|
        # Find the corresponding parent charge with the same billable_metric
        parent_charge = parent_plan.charges.find_by(
          billable_metric_id: child_charge.billable_metric_id
        )

        expect(parent_charge).to be_present
        expect(child_charge.parent_id).to eq(parent_charge.id)
      end
    end

    # Verify that all child plans have the same total number of charges
    # (original charges + 2 new charges)
    child_plans.each do |child_plan|
      child_plan.reload
      expect(child_plan.charges.count).to eq(22) # 20 original + 2 new
    end
  end
end
