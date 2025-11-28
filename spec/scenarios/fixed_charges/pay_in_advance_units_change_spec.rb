# frozen_string_literal: true

require "rails_helper"

describe "Pay in advance fixed charge units change mid-period" do
  around { |test| lago_premium!(&test) }

  let(:organization) { create(:organization, webhook_url: nil) }
  let(:customer) { create(:customer, organization:, timezone: "UTC") }
  let(:add_on) { create(:add_on, organization:) }
  let(:plan) do
    create(
      :plan,
      organization:,
      amount_cents: 0,
      interval: "monthly",
      pay_in_advance: true
    )
  end

  # Fixed charge: $10 per unit, 10 units, pay in advance, not prorated
  let(:fixed_charge) do
    create(
      :fixed_charge,
      plan:,
      add_on:,
      units: 10,
      properties: {amount: "10"},
      prorated: false,
      pay_in_advance: true
    )
  end

  describe "when units change mid-period with apply_units_immediately: true" do
    let(:subscription_date) { DateTime.new(2024, 3, 1) }
    let(:subscription) { customer.subscriptions.first }

    before do
      fixed_charge

      # Create subscription at the start of the month
      travel_to subscription_date do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: "sub_#{customer.external_id}",
            plan_code: plan.code,
            billing_time: "calendar"
          }
        )
      end

      # Process the initial invoice
      travel_to subscription_date + 1.minute do
        perform_all_enqueued_jobs
      end
    end

    it "generates initial invoice with 10 units" do
      expect(subscription.invoices.count).to eq(1)
      initial_invoice = subscription.invoices.first

      expect(initial_invoice.fees.fixed_charge.count).to eq(1)
      fee = initial_invoice.fees.fixed_charge.first

      # 10 units * $10 = $100 = 10000 cents
      expect(fee.units).to eq(10)
      expect(fee.amount_cents).to eq(10_000)

      # Verify invoice total matches sum of fees
      expect(initial_invoice.fees_amount_cents).to eq(initial_invoice.fees.sum(:amount_cents))
      expect(initial_invoice.fees_amount_cents).to eq(10_000)
    end

    context "when decreasing units from 10 to 5" do
      before do
        travel_to subscription_date + 5.days do
          update_plan(
            plan,
            {
              fixed_charges: [{
                id: fixed_charge.id,
                units: 5,
                apply_units_immediately: true,
                properties: {amount: "10"}
              }]
            }
          )

          perform_all_enqueued_jobs
        end
      end

      it "creates a new fixed charge event with units 5" do
        events = FixedChargeEvent.where(subscription:, fixed_charge:).order(:created_at)
        expect(events.count).to eq(2)
        expect(events.last.units).to eq(5)
      end

      it "generates a zero-amount invoice when units decrease" do
        # After decreasing units, we expect a new invoice with zero amount
        # because we don't refund pay-in-advance fixed charges
        expect(subscription.reload.invoices.count).to eq(2)

        adjustment_invoice = subscription.invoices.order(:created_at).last
        expect(adjustment_invoice.fees.count).to eq(0)
        expect(adjustment_invoice.fees_amount_cents).to eq(0)
      end
    end

    context "when increasing units from 10 to 15" do
      before do
        travel_to subscription_date + 5.days do
          update_plan(
            plan,
            {
              fixed_charges: [{
                id: fixed_charge.id,
                units: 15,
                apply_units_immediately: true,
                properties: {amount: "10"}
              }]
            }
          )
          perform_all_enqueued_jobs
        end
      end

      it "creates a new fixed charge event with units 15" do
        events = FixedChargeEvent.where(subscription:, fixed_charge:).order(:created_at)
        expect(events.count).to eq(2)
        expect(events.last.units).to eq(15)
      end

      it "generates an invoice for the additional units only (delta billing)" do
        # After increasing units from 10 to 15, we expect a new invoice
        # for the 5 additional units only: 5 * $10 = $50 = 5000 cents
        expect(subscription.reload.invoices.count).to eq(2)

        adjustment_invoice = subscription.invoices.order(:created_at).last
        expect(adjustment_invoice.fees.fixed_charge.count).to eq(1)

        fee = adjustment_invoice.fees.fixed_charge.first
        expect(fee.units).to eq(5)  # Only the delta
        expect(fee.amount_cents).to eq(5_000)  # 5 units * $10 = $50

        # Verify invoice total matches sum of fees
        expect(adjustment_invoice.fees_amount_cents).to eq(adjustment_invoice.fees.sum(:amount_cents))
        expect(adjustment_invoice.fees_amount_cents).to eq(5_000)
      end
    end

    context "when decreasing then increasing units (10 -> 5 -> 15)" do
      before do
        # First decrease to 5
        travel_to subscription_date + 5.days do
          update_plan(
            plan,
            {
              fixed_charges: [{
                id: fixed_charge.id,
                units: 5,
                apply_units_immediately: true,
                properties: {amount: "10"}
              }]
            }
          )
          perform_all_enqueued_jobs
        end

        # Then increase to 15
        travel_to subscription_date + 10.days do
          update_plan(
            plan,
            {
              fixed_charges: [{
                id: fixed_charge.id,
                units: 15,
                apply_units_immediately: true,
                properties: {amount: "10"}
              }]
            }
          )
          perform_all_enqueued_jobs
        end
      end

      it "creates fixed charge events for each change" do
        events = FixedChargeEvent.where(subscription:, fixed_charge:).order(:created_at)
        expect(events.count).to eq(3)
        expect(events.map(&:units)).to eq([10, 5, 15])
      end

      it "generates invoice for delta from originally paid units (not current units)" do
        # After all changes:
        # - Initial: paid for 10 units
        # - Decrease to 5: no refund, so still paid for 10 units
        # - Increase to 15: should charge for 15 - 10 = 5 units only
        invoices = subscription.reload.invoices.order(:created_at)

        # We expect 3 invoices:
        # 1. Initial invoice (10 units, $100)
        # 2. Decrease invoice (0 amount - no refund)
        # 3. Increase invoice (5 units delta, $50)
        expect(invoices.count).to eq(3)

        initial_invoice = invoices.first
        expect(initial_invoice.fees.fixed_charge.first.units).to eq(10)
        expect(initial_invoice.fees.fixed_charge.first.amount_cents).to eq(10_000)
        expect(initial_invoice.fees_amount_cents).to eq(initial_invoice.fees.sum(:amount_cents))
        expect(initial_invoice.fees_amount_cents).to eq(10_000)

        decrease_invoice = invoices.second
        expect(decrease_invoice.fees.count).to eq(0)
        expect(decrease_invoice.fees_amount_cents).to eq(0)

        increase_invoice = invoices.last
        # This is the critical assertion: we should only charge for 5 units (15 - 10),
        # NOT 10 units (15 - 5), because we never refunded when going from 10 to 5
        expect(increase_invoice.fees.fixed_charge.first.units).to eq(5)
        expect(increase_invoice.fees.fixed_charge.first.amount_cents).to eq(5_000)
        expect(increase_invoice.fees_amount_cents).to eq(increase_invoice.fees.sum(:amount_cents))
        expect(increase_invoice.fees_amount_cents).to eq(5_000)
      end
    end

    context "when increasing units multiple times (10 -> 15 -> 20)" do
      before do
        # First increase to 15
        travel_to subscription_date + 5.days do
          update_plan(
            plan,
            {
              fixed_charges: [{
                id: fixed_charge.id,
                units: 15,
                apply_units_immediately: true,
                properties: {amount: "10"}
              }]
            }
          )
          perform_all_enqueued_jobs
        end

        # Then increase to 20
        travel_to subscription_date + 10.days do
          update_plan(
            plan,
            {
              fixed_charges: [{
                id: fixed_charge.id,
                units: 20,
                apply_units_immediately: true,
                properties: {amount: "10"}
              }]
            }
          )
          perform_all_enqueued_jobs
        end
      end

      it "generates invoices for each delta increase" do
        invoices = subscription.reload.invoices.order(:created_at)

        # We expect 3 invoices:
        # 1. Initial invoice (10 units, $100)
        # 2. First increase invoice (5 units delta: 15 - 10, $50)
        # 3. Second increase invoice (5 units delta: 20 - 15, $50)
        expect(invoices.count).to eq(3)

        initial_invoice = invoices.first
        expect(initial_invoice.fees.fixed_charge.first.units).to eq(10)
        expect(initial_invoice.fees.fixed_charge.first.amount_cents).to eq(10_000)
        expect(initial_invoice.fees_amount_cents).to eq(initial_invoice.fees.sum(:amount_cents))
        expect(initial_invoice.fees_amount_cents).to eq(10_000)

        first_increase_invoice = invoices.second
        expect(first_increase_invoice.fees.fixed_charge.first.units).to eq(5)
        expect(first_increase_invoice.fees.fixed_charge.first.amount_cents).to eq(5_000)
        expect(first_increase_invoice.fees_amount_cents).to eq(first_increase_invoice.fees.sum(:amount_cents))
        expect(first_increase_invoice.fees_amount_cents).to eq(5_000)

        second_increase_invoice = invoices.last
        expect(second_increase_invoice.fees.fixed_charge.first.units).to eq(5)
        expect(second_increase_invoice.fees.fixed_charge.first.amount_cents).to eq(5_000)
        expect(second_increase_invoice.fees_amount_cents).to eq(second_increase_invoice.fees.sum(:amount_cents))
        expect(second_increase_invoice.fees_amount_cents).to eq(5_000)
      end
    end
  end

  describe "when multiple fixed charges are updated at once via plan update" do
    let(:add_on2) { create(:add_on, organization:) }
    let(:subscription_date) { DateTime.new(2024, 3, 1) }
    let(:subscription) { customer.subscriptions.first }

    # Second fixed charge: $20 per unit, 5 units, pay in advance
    let(:fixed_charge2) do
      create(
        :fixed_charge,
        plan:,
        add_on: add_on2,
        units: 5,
        properties: {amount: "20"},
        pay_in_advance: true
      )
    end

    before do
      fixed_charge
      fixed_charge2

      # Create subscription at the start of the month
      travel_to subscription_date do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: "sub_multi_#{customer.external_id}",
            plan_code: plan.code,
            billing_time: "calendar"
          }
        )
      end

      # Process the initial invoice
      travel_to subscription_date + 1.minute do
        perform_all_enqueued_jobs
      end
    end

    it "generates initial invoice with fees for both fixed charges" do
      expect(subscription.invoices.count).to eq(1)
      initial_invoice = subscription.invoices.first

      expect(initial_invoice.fees.fixed_charge.count).to eq(2)

      fee1 = initial_invoice.fees.fixed_charge.find_by(fixed_charge: fixed_charge)
      fee2 = initial_invoice.fees.fixed_charge.find_by(fixed_charge: fixed_charge2)

      # First fixed charge: 10 units * $10 = $100
      expect(fee1.units).to eq(10)
      expect(fee1.amount_cents).to eq(10_000)

      # Second fixed charge: 5 units * $20 = $100
      expect(fee2.units).to eq(5)
      expect(fee2.amount_cents).to eq(10_000)

      # Verify invoice total matches sum of fees ($100 + $100 = $200)
      expect(initial_invoice.fees_amount_cents).to eq(initial_invoice.fees.sum(:amount_cents))
      expect(initial_invoice.fees_amount_cents).to eq(20_000)
    end

    context "when both fixed charges are updated via plan update" do
      before do
        travel_to subscription_date + 5.days do
          # Update plan with both fixed charges having apply_units_immediately: true
          update_plan(
            plan,
            {
              fixed_charges: [
                {
                  id: fixed_charge.id,
                  units: 15,
                  apply_units_immediately: true,
                  properties: {amount: "10"}
                },
                {
                  id: fixed_charge2.id,
                  units: 10,
                  apply_units_immediately: true,
                  properties: {amount: "20"}
                }
              ]
            }
          )
          perform_all_enqueued_jobs
        end
      end

      it "generates a SINGLE invoice with fees for both fixed charge deltas" do
        invoices = subscription.reload.invoices.order(:created_at)

        # We expect 2 invoices:
        # 1. Initial invoice (both fixed charges)
        # 2. ONE invoice with both fixed charges units deltas
        expect(invoices.count).to eq(2)

        batched_invoice = invoices.last
        expect(batched_invoice.fees.count).to eq(2)

        fee1 = batched_invoice.fees.fixed_charge.find_by(fixed_charge: fixed_charge)
        fee2 = batched_invoice.fees.fixed_charge.find_by(fixed_charge: fixed_charge2)

        # First fixed charge delta: 15 - 10 = 5 units * $10 = $50
        expect(fee1.units).to eq(5)
        expect(fee1.amount_cents).to eq(5_000)

        # Second fixed charge delta: 10 - 5 = 5 units * $20 = $100
        expect(fee2.units).to eq(5)
        expect(fee2.amount_cents).to eq(10_000)

        # Verify invoice total matches sum of fees ($50 + $100 = $150)
        expect(batched_invoice.fees_amount_cents).to eq(batched_invoice.fees.sum(:amount_cents))
        expect(batched_invoice.fees_amount_cents).to eq(15_000)
      end
    end
  end

  describe "when adding and updating fix charges with apply units immediately" do
    let(:add_on2) { create(:add_on, organization:) }
    let(:subscription_date) { DateTime.new(2024, 3, 1) }
    let(:subscription) { customer.subscriptions.first }

    before do
      fixed_charge

      # Create subscription at the start of the month with one fixed charge
      travel_to subscription_date do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: "sub_add_update_#{customer.external_id}",
            plan_code: plan.code,
            billing_time: "calendar"
          }
        )
      end

      # Process the initial invoice
      travel_to subscription_date + 1.minute do
        perform_all_enqueued_jobs
      end
    end

    context "when updating existing fixed charge AND adding a new fixed charge" do
      before do
        travel_to subscription_date + 5.days do
          # Update the plan to:
          # 1. Update existing fixed charge from 10 to 15 units
          # 2. Add a new fixed charge with 8 units at $5 each
          update_plan(
            plan,
            {
              fixed_charges: [
                {
                  id: fixed_charge.id,
                  units: 15,
                  apply_units_immediately: true,
                  properties: {amount: "10"}
                },
                {
                  add_on_id: add_on2.id,
                  invoice_display_name: "New Fixed Charge",
                  charge_model: "standard",
                  units: 8,
                  properties: {amount: "5"},
                  pay_in_advance: true,
                  apply_units_immediately: true
                }
              ]
            }
          )
          perform_all_enqueued_jobs
        end
      end

      it "generates a SINGLE invoice with fees for both updated and new fixed charges" do
        new_fixed_charge = plan.fixed_charges.find_by(add_on: add_on2)
        invoices = subscription.reload.invoices.order(:created_at)

        # We expect 2 invoices:
        # 1. Initial invoice (original fixed charge only)
        # 2. ONE invoice with delta for updated + full for new
        expect(invoices.count).to eq(2)

        combined_invoice = invoices.last
        expect(combined_invoice.fees.count).to eq(2)

        updated_fixed_charge_fee = combined_invoice.fees.fixed_charge.find_by(fixed_charge:)
        new_fixed_charge_fee = combined_invoice.fees.fixed_charge.find_by(fixed_charge: new_fixed_charge)

        # Updated fixed charge: delta only (15 - 10 = 5 units * $10 = $50)
        expect(updated_fixed_charge_fee.units).to eq(5)
        expect(updated_fixed_charge_fee.amount_cents).to eq(5_000)

        # New fixed charge: full amount (8 units * $5 = $40)
        expect(new_fixed_charge_fee.units).to eq(8)
        expect(new_fixed_charge_fee.amount_cents).to eq(4_000)

        # Total: $50 + $40 = $90
        expect(combined_invoice.fees_amount_cents).to eq(combined_invoice.fees.sum(:amount_cents))
        expect(combined_invoice.fees_amount_cents).to eq(9_000)
      end
    end

    context "when only adding a new fixed charge (no updates to existing)" do
      before do
        travel_to subscription_date + 5.days do
          # Add a new fixed charge without updating the existing one
          update_plan(
            plan,
            {
              fixed_charges: [
                {
                  id: fixed_charge.id,
                  units: 10,  # Same as before
                  properties: {amount: "10"}
                },
                {
                  add_on_id: add_on2.id,
                  invoice_display_name: "New Fixed Charge",
                  charge_model: "standard",
                  units: 6,
                  properties: {amount: "15"},
                  pay_in_advance: true,
                  apply_units_immediately: true
                }
              ]
            }
          )
          perform_all_enqueued_jobs
        end
      end

      it "generates an invoice only for the new fixed charge" do
        new_fixed_charge = plan.fixed_charges.find_by(add_on: add_on2)
        invoices = subscription.reload.invoices.order(:created_at)

        expect(invoices.count).to eq(2)

        new_charge_invoice = invoices.last
        expect(new_charge_invoice.fees.count).to eq(1)

        fee = new_charge_invoice.fees.fixed_charge.first
        expect(fee.fixed_charge).to eq(new_fixed_charge)

        # New fixed charge: 6 units * $15 = $90
        expect(fee.units).to eq(6)
        expect(fee.amount_cents).to eq(9_000)

        expect(new_charge_invoice.fees_amount_cents).to eq(9_000)
      end
    end
  end

  describe "when updating fixed charge with apply changes on next period" do
    let(:subscription_date) { DateTime.new(2024, 3, 1) }
    let(:subscription) { customer.subscriptions.first }

    before do
      fixed_charge

      # Create subscription at the start of the month
      travel_to subscription_date do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: "sub_next_period_#{customer.external_id}",
            plan_code: plan.code,
            billing_time: "calendar"
          }
        )
      end

      # Process the initial invoice
      travel_to subscription_date + 1.minute do
        perform_all_enqueued_jobs
      end

      travel_to subscription_date + 5.days do
        # Update the fixed charge units WITHOUT apply_units_immediately
        update_plan(
          plan,
          {
            fixed_charges: [{
              id: fixed_charge.id,
              units: 15,
              # No apply_units_immediately - changes apply next period
              properties: {amount: "10"}
            }]
          }
        )
        perform_all_enqueued_jobs
      end
    end

    it "does NOT generate a new invoice mid-period" do
      invoices = subscription.reload.invoices.order(:created_at)

      # Only the initial invoice should exist
      expect(invoices.count).to eq(1)

      initial_invoice = invoices.first
      expect(initial_invoice.fees.fixed_charge.count).to eq(1)
      expect(initial_invoice.fees.fixed_charge.first.units).to eq(10)
      expect(initial_invoice.fees_amount_cents).to eq(10_000)
    end

    it "creates a fixed charge event for the updated charge at next billing period" do
      events = FixedChargeEvent.where(subscription:, fixed_charge:).order(:timestamp)

      expect(events.count).to eq(2)
      expect(events.first.units).to eq(10)
      expect(events.first.timestamp).to be < subscription_date.end_of_month
      expect(events.last.units).to eq(15)
      expect(events.last.timestamp).to be > subscription_date.end_of_month
    end
  end

  describe "when adding fixed charge with apply changes on next period" do
    let(:add_on2) { create(:add_on, organization:) }
    let(:subscription_date) { DateTime.new(2024, 3, 1) }
    let(:subscription) { customer.subscriptions.first }

    before do
      fixed_charge

      # Create subscription at the start of the month
      travel_to subscription_date do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: "sub_next_period_#{customer.external_id}",
            plan_code: plan.code,
            billing_time: "calendar"
          }
        )
      end

      # Process the initial invoice
      travel_to subscription_date + 1.minute do
        perform_all_enqueued_jobs
      end

      travel_to subscription_date + 5.days do
        # Add a new fixed charge without apply_units_immediately
        update_plan(
          plan,
          {
            fixed_charges: [
              {
                id: fixed_charge.id,
                units: 10,  # No change to existing
                properties: {amount: "10"}
              },
              {
                add_on_id: add_on2.id,
                invoice_display_name: "New Fixed Charge",
                charge_model: "standard",
                units: 8,
                properties: {amount: "5"},
                pay_in_advance: true
                # No apply_units_immediately
              }
            ]
          }
        )
        perform_all_enqueued_jobs
      end
    end

    it "does NOT generate a new invoice mid-period" do
      invoices = subscription.reload.invoices.order(:created_at)

      # Only the initial invoice should exist
      expect(invoices.count).to eq(1)
    end

    it "creates a fixed charge event for the new charge at next billing period" do
      new_fixed_charge = plan.fixed_charges.find_by(add_on: add_on2)
      events = FixedChargeEvent.where(subscription:, fixed_charge: new_fixed_charge).order(:timestamp)

      expect(events.count).to eq(1)
      expect(events.first.units).to eq(8)
      # Event should be scheduled for next billing period
      expect(events.first.timestamp).to be > subscription_date.end_of_month
    end
  end

  describe "when updating multiple fixed charges units with children plans" do
    let(:add_on2) { create(:add_on, organization:) }
    let(:subscription_date) { DateTime.new(2024, 3, 1) }

    # Second fixed charge: $20 per unit, 5 units, pay in advance
    let(:fixed_charge2) do
      create(
        :fixed_charge,
        plan:,
        add_on: add_on2,
        units: 5,
        properties: {amount: "20"},
        pay_in_advance: true
      )
    end

    # Parent plan setup
    let(:parent_plan) { plan }
    let(:parent_subscription) { customer.subscriptions.first }

    # Second customer for child subscription
    let(:customer2) { create(:customer, organization:, timezone: "UTC") }
    let(:child_subscription) { customer2.subscriptions.first }

    before do
      fixed_charge
      fixed_charge2

      # Create parent subscription
      travel_to subscription_date do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: "sub_parent_#{customer.external_id}",
            plan_code: parent_plan.code,
            billing_time: "calendar"
          }
        )

        # Create child subscription using plan_overrides (creates a child plan)
        create_subscription(
          {
            external_customer_id: customer2.external_id,
            external_id: "sub_child_#{customer2.external_id}",
            plan_code: parent_plan.code,
            billing_time: "calendar",
            plan_overrides: {
              name: "Child Plan Override",
              fixed_charges: [{
                id: fixed_charge.id,
                units: 20
              }]
            }
          }
        )
      end

      # Process initial invoices
      travel_to subscription_date + 1.minute do
        perform_all_enqueued_jobs
      end
    end

    it "generates initial invoices for both parent and child subscriptions" do
      expect(parent_subscription.invoices.count).to eq(1)
      expect(child_subscription.invoices.count).to eq(1)

      parent_invoice = parent_subscription.invoices.first
      child_invoice = child_subscription.invoices.first

      parent_fixed_charge_fee_1 = parent_invoice.fees.fixed_charge.find_by(fixed_charge:)
      parent_fixed_charge_fee_2 = parent_invoice.fees.fixed_charge.find_by(fixed_charge: fixed_charge2)

      expect(parent_fixed_charge_fee_1.units).to eq(10)
      expect(parent_fixed_charge_fee_2.units).to eq(5)

      child_fixed_charge_1 = child_subscription.fixed_charges.find_by(parent: fixed_charge)
      child_fixed_charge_2 = child_subscription.fixed_charges.find_by(parent: fixed_charge2)
      child_fixed_charge_fee_1 = child_invoice.fees.fixed_charge.find_by(fixed_charge: child_fixed_charge_1)
      child_fixed_charge_fee_2 = child_invoice.fees.fixed_charge.find_by(fixed_charge: child_fixed_charge_2)

      expect(child_fixed_charge_fee_1.units).to eq(20)
      expect(child_fixed_charge_fee_2.units).to eq(5)
    end

    context "when parent plan fixed charge is updated with apply_units_immediately and cascade" do
      let(:child_fixed_charge1) { child_subscription.fixed_charges.find_by(parent: fixed_charge) }
      let(:child_fixed_charge2) { child_subscription.fixed_charges.find_by(parent: fixed_charge2) }

      before do
        travel_to subscription_date + 5.days do
          # Update parent plan with cascade
          update_plan(
            parent_plan,
            {
              cascade_updates: true,
              fixed_charges: [
                {
                  id: fixed_charge.id,
                  units: 25,
                  apply_units_immediately: true,
                  properties: {amount: "10"},
                  charge_model: "standard"
                },
                {
                  id: fixed_charge2.id,
                  units: 15,
                  apply_units_immediately: true,
                  properties: {amount: "20"},
                  charge_model: "standard"
                }
              ]
            }
          )
          perform_all_enqueued_jobs
        end
      end

      it "updates the child fixed charges units" do
        expect(child_fixed_charge1.reload.units).to eq(25)
        expect(child_fixed_charge2.reload.units).to eq(15)
      end

      it "creates fixed charge events for both parent and child subscriptions" do
        # Parent events
        parent_events_1 = FixedChargeEvent.where(subscription: parent_subscription, fixed_charge:).order(:timestamp)
        expect(parent_events_1.count).to eq(2)
        expect(parent_events_1.last.units).to eq(25)

        parent_events_2 = FixedChargeEvent.where(subscription: parent_subscription, fixed_charge: fixed_charge2).order(:timestamp)
        expect(parent_events_2.count).to eq(2)
        expect(parent_events_2.last.units).to eq(15)

        # Child events
        child_events_1 = FixedChargeEvent.where(subscription: child_subscription, fixed_charge: child_fixed_charge1).order(:timestamp)
        expect(child_events_1.count).to eq(2)
        expect(child_events_1.last.units).to eq(25)

        child_events_2 = FixedChargeEvent.where(subscription: child_subscription, fixed_charge: child_fixed_charge2).order(:timestamp)
        expect(child_events_2.count).to eq(2)
        expect(child_events_2.last.units).to eq(15)
      end

      it "generates a single delta invoices for each parent and child subscriptions" do
        # Parent should have 2 invoices (initial + delta for both fixed charges)
        parent_invoices = parent_subscription.reload.invoices.order(:created_at)
        expect(parent_invoices.count).to eq(2)

        parent_delta_invoice = parent_invoices.last
        expect(parent_delta_invoice.fees.count).to eq(2)

        parent_fixed_charge_fee_1 = parent_delta_invoice.fees.fixed_charge.find_by(fixed_charge:)
        parent_fixed_charge_fee_2 = parent_delta_invoice.fees.fixed_charge.find_by(fixed_charge: fixed_charge2)

        expect(parent_fixed_charge_fee_1.units).to eq(15)  # 25 - 10 = 15
        expect(parent_fixed_charge_fee_1.amount_cents).to eq(15_000)
        expect(parent_fixed_charge_fee_2.units).to eq(10)  # 15 - 5 = 10
        expect(parent_fixed_charge_fee_2.amount_cents).to eq(20_000)

        # Child should also have 2 invoices (initial + delta for both fixed charges)
        child_invoices = child_subscription.reload.invoices.order(:created_at)
        expect(child_invoices.count).to eq(2)

        child_delta_invoice = child_invoices.last
        expect(child_delta_invoice.fees.count).to eq(2)

        child_fixed_charge_fee_1 = child_delta_invoice.fees.fixed_charge.find_by(fixed_charge: child_fixed_charge1)
        child_fixed_charge_fee_2 = child_delta_invoice.fees.fixed_charge.find_by(fixed_charge: child_fixed_charge2)

        expect(child_fixed_charge_fee_1.units).to eq(5)  # 25 - 20 = 5
        expect(child_fixed_charge_fee_1.amount_cents).to eq(5_000)
        expect(child_fixed_charge_fee_2.units).to eq(10)  # 15 - 5 = 10
        expect(child_fixed_charge_fee_2.amount_cents).to eq(20_000)
      end
    end

    context "when parent plan fixed charge is updated WITHOUT cascade" do
      before do
        travel_to subscription_date + 5.days do
          # Update parent plan WITHOUT cascade
          update_plan(
            parent_plan,
            {
              cascade_updates: false,
              fixed_charges: [{
                id: fixed_charge.id,
                units: 15,
                apply_units_immediately: true,
                properties: {amount: "10"},
                charge_model: "standard"
              }]
            }
          )
          perform_all_enqueued_jobs
        end
      end

      it "does NOT update the child fixed charge units" do
        child_fixed_charge1 = child_subscription.fixed_charges.find_by(parent: fixed_charge)

        expect(fixed_charge.reload.units).to eq(15)
        expect(child_fixed_charge1.reload.units).to eq(20)  # Unchanged
      end

      it "generates delta invoice only for parent subscription" do
        # Parent should have 2 invoices
        parent_invoices = parent_subscription.reload.invoices.order(:created_at)
        expect(parent_invoices.count).to eq(2)

        # Child should still have only 1 invoice (initial only)
        child_invoices = child_subscription.reload.invoices.order(:created_at)
        expect(child_invoices.count).to eq(1)
      end
    end
  end

  describe "when adding multiple fixed charges with children plans" do
    let(:add_on2) { create(:add_on, organization:) }
    let(:add_on3) { create(:add_on, organization:) }
    let(:subscription_date) { DateTime.new(2024, 3, 1) }

    # Parent plan setup
    let(:parent_plan) { plan }
    let(:parent_subscription) { customer.subscriptions.first }

    # Second customer for child subscription
    let(:customer2) { create(:customer, organization:, timezone: "UTC") }
    let(:child_subscription) { customer2.subscriptions.first }

    before do
      fixed_charge

      # Create parent subscription
      travel_to subscription_date do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: "sub_parent_#{customer.external_id}",
            plan_code: parent_plan.code,
            billing_time: "calendar"
          }
        )

        # Create child subscription using plan_overrides (creates a child plan)
        create_subscription(
          {
            external_customer_id: customer2.external_id,
            external_id: "sub_child_#{customer2.external_id}",
            plan_code: parent_plan.code,
            billing_time: "calendar",
            plan_overrides: {
              name: "Child Plan Override",
              fixed_charges: [{
                id: fixed_charge.id,
                units: 20
              }]
            }
          }
        )
      end

      # Process initial invoices
      travel_to subscription_date + 1.minute do
        perform_all_enqueued_jobs
      end
    end

    it "generates initial invoices for both parent and child subscriptions" do
      expect(parent_subscription.invoices.count).to eq(1)
      expect(child_subscription.invoices.count).to eq(1)

      parent_invoice = parent_subscription.invoices.first
      child_invoice = child_subscription.invoices.first

      expect(parent_invoice.fees.fixed_charge.count).to eq(1)
      expect(parent_invoice.fees.fixed_charge.first.units).to eq(10)

      expect(child_invoice.fees.fixed_charge.count).to eq(1)
      expect(child_invoice.fees.fixed_charge.first.units).to eq(20)
    end

    context "when update parent plan with new fixed charges with apply_units_immediately and cascade" do
      let(:fixed_charge2) { parent_plan.fixed_charges.find_by(add_on: add_on2) }
      let(:fixed_charge3) { parent_plan.fixed_charges.find_by(add_on: add_on3) }
      let(:child_fixed_charge2) { child_subscription.fixed_charges.find_by(parent: fixed_charge2) }
      let(:child_fixed_charge3) { child_subscription.fixed_charges.find_by(parent: fixed_charge3) }

      before do
        travel_to subscription_date + 5.days do
          # Update parent plan with cascade
          update_plan(
            parent_plan,
            {
              cascade_updates: true,
              fixed_charges: [
                {
                  add_on_id: add_on2.id,
                  invoice_display_name: "New Fixed Charge",
                  charge_model: "standard",
                  units: 8,
                  properties: {amount: "5"},
                  pay_in_advance: true,
                  apply_units_immediately: true
                },
                {
                  add_on_id: add_on3.id,
                  invoice_display_name: "New Fixed Charge 2",
                  charge_model: "standard",
                  units: 33,
                  properties: {amount: "2"},
                  pay_in_advance: true,
                  apply_units_immediately: true
                }
              ]
            }
          )
          perform_all_enqueued_jobs
        end
      end

      it "updates the child fixed charges units" do
        expect(child_fixed_charge2.reload.units).to eq(8)
        expect(child_fixed_charge3.reload.units).to eq(33)
      end

      it "creates fixed charge events for both parent and child subscriptions" do
        # Parent events
        parent_events_2 = FixedChargeEvent.where(subscription: parent_subscription, fixed_charge: fixed_charge2).order(:timestamp)
        expect(parent_events_2.count).to eq(1)
        expect(parent_events_2.last.units).to eq(8)

        parent_events_3 = FixedChargeEvent.where(subscription: parent_subscription, fixed_charge: fixed_charge3).order(:timestamp)
        expect(parent_events_3.count).to eq(1)
        expect(parent_events_3.last.units).to eq(33)

        # Child events
        child_events_2 = FixedChargeEvent.where(subscription: child_subscription, fixed_charge: child_fixed_charge2).order(:timestamp)
        expect(child_events_2.count).to eq(1)
        expect(child_events_2.last.units).to eq(8)

        child_events_3 = FixedChargeEvent.where(subscription: child_subscription, fixed_charge: child_fixed_charge3).order(:timestamp)
        expect(child_events_3.count).to eq(1)
        expect(child_events_3.last.units).to eq(33)
      end

      it "generates a single delta invoices for each, parent and child subscriptions" do
        # Parent should have 2 invoices (initial + delta for both fixed charges)
        parent_invoices = parent_subscription.reload.invoices.order(:created_at)
        expect(parent_invoices.count).to eq(2)

        parent_delta_invoice = parent_invoices.last
        expect(parent_delta_invoice.fees.count).to eq(2)

        parent_fixed_charge_fee_2 = parent_delta_invoice.fees.fixed_charge.find_by(fixed_charge: fixed_charge2)
        parent_fixed_charge_fee_3 = parent_delta_invoice.fees.fixed_charge.find_by(fixed_charge: fixed_charge3)

        expect(parent_fixed_charge_fee_2.units).to eq(8)
        expect(parent_fixed_charge_fee_2.amount_cents).to eq(4000)
        expect(parent_fixed_charge_fee_3.units).to eq(33)
        expect(parent_fixed_charge_fee_3.amount_cents).to eq(6600)

        # Child should also have 2 invoices (initial + delta for both fixed charges)
        child_invoices = child_subscription.reload.invoices.order(:created_at)
        expect(child_invoices.count).to eq(2)

        child_delta_invoice = child_invoices.last
        expect(child_delta_invoice.fees.count).to eq(2)

        child_fixed_charge_fee_2 = child_delta_invoice.fees.fixed_charge.find_by(fixed_charge: child_fixed_charge2)
        child_fixed_charge_fee_3 = child_delta_invoice.fees.fixed_charge.find_by(fixed_charge: child_fixed_charge3)

        expect(child_fixed_charge_fee_2.units).to eq(8)
        expect(child_fixed_charge_fee_2.amount_cents).to eq(4000)
        expect(child_fixed_charge_fee_3.units).to eq(33)
        expect(child_fixed_charge_fee_3.amount_cents).to eq(6600)
      end
    end

    context "when parent plan fixed charge is created WITHOUT cascade" do
      before do
        travel_to subscription_date + 5.days do
          # Update parent plan WITHOUT cascade
          update_plan(
            parent_plan,
            {
              cascade_updates: false,
              fixed_charges: [{
                add_on_id: add_on2.id,
                invoice_display_name: "New Fixed Charge",
                charge_model: "standard",
                units: 8,
                properties: {amount: "5"},
                pay_in_advance: true,
                apply_units_immediately: true
              }]
            }
          )
          perform_all_enqueued_jobs
        end
      end

      it "does NOT update the child fixed charge units" do
        expect(child_subscription.fixed_charges.count).to eq(1)
      end

      it "generates delta invoice only for parent subscription" do
        # Parent should have 2 invoices
        parent_invoices = parent_subscription.reload.invoices.order(:created_at)
        expect(parent_invoices.count).to eq(2)

        # Child should still have only 1 invoice (initial only)
        child_invoices = child_subscription.reload.invoices.order(:created_at)
        expect(child_invoices.count).to eq(1)
      end
    end
  end
end
