# frozen_string_literal: true

require "rails_helper"

describe "Subscription fixed charge units override via subscription endpoint", :premium do
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

  let(:subscription_date) { DateTime.new(2024, 3, 1) }
  let(:subscription) { customer.subscriptions.first }

  before do
    fixed_charge

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

    travel_to subscription_date + 1.minute do
      perform_all_enqueued_jobs
    end
  end

  context "when units are updated through the subscription endpoint" do
    let(:override) { subscription.fixed_charge_units_overrides.first }

    before do
      travel_to subscription_date + 5.days do
        update_subscription_fixed_charge(
          subscription,
          fixed_charge.code,
          {
            units: 15,
            apply_units_immediately: true
          }
        )

        perform_all_enqueued_jobs
      end
    end

    it "does not create a plan override" do
      expect(subscription.reload.plan_id).to eq(plan.id)
      expect(Plan.where(parent_id: plan.id)).to be_empty
    end

    it "does not create a fixed charge override" do
      expect(FixedCharge.where(parent_id: fixed_charge.id)).to be_empty
    end

    it "creates a SubscriptionFixedChargeUnitsOverride for the pair" do
      expect(subscription.fixed_charge_units_overrides.count).to eq(1)
      expect(override.fixed_charge).to eq(fixed_charge)
      expect(override.units).to eq(15)
    end

    it "emits a fixed charge event with the override units" do
      events = FixedChargeEvent.where(subscription:, fixed_charge:).order(:created_at)
      expect(events.count).to eq(2)
      expect(events.last.units).to eq(15)
    end
  end
end
