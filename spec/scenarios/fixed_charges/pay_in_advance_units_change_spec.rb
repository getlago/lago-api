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

  xdescribe "when updating a fixed charge with apply changes on next period"
  xdescribe "when adding a fixed charge with apply units on next period"
  xdescribe "when updating a fixed charge unit with plan children"
  xdescribe "when adding a fixed charge unit with plan children"
end
