# frozen_string_literal: true

require "rails_helper"

describe "Rate Schedules Multiple Rate Schedules" do
  include_context "with rate schedule billing"

  let(:billing_interval_unit) { "month" }

  describe "rate schedule succession on the same product item" do
    # Subscription fee with 3 rate schedules chained:
    #   RS1: 10€, weekly,  2 cycles  (active)
    #   RS2: 20€, monthly, 2 cycles  (pending → active after RS1 exhausts)
    #   RS3: 30€, quarterly, ongoing (pending → active after RS2 exhausts)

    let(:rate_schedule_1) do
      create(
        :rate_schedule,
        organization:,
        plan_product_item:,
        product_item: subscription_item,
        charge_model: "standard",
        billing_interval_unit: "week",
        billing_interval_count: 1,
        amount_currency: "EUR",
        properties: {"amount" => "10.00"},
        position: 0
      )
    end

    let(:rate_schedule_2) do
      create(
        :rate_schedule,
        organization:,
        plan_product_item:,
        product_item: subscription_item,
        charge_model: "standard",
        billing_interval_unit: "month",
        billing_interval_count: 1,
        amount_currency: "EUR",
        properties: {"amount" => "20.00"},
        position: 1
      )
    end

    let(:rate_schedule_3) do
      create(
        :rate_schedule,
        organization:,
        plan_product_item:,
        product_item: subscription_item,
        charge_model: "standard",
        billing_interval_unit: "month",
        billing_interval_count: 3,
        amount_currency: "EUR",
        properties: {"amount" => "30.00"},
        position: 2
      )
    end

    # Override the default rate_schedule so the before block doesn't create it
    let(:rate_schedule) { rate_schedule_1 }

    before do
      rate_schedule_2
      rate_schedule_3
    end

    it "chains through rate schedules as each one exhausts its cycles" do
      subscription = nil

      # Subscription starts Jan 1
      travel_to(DateTime.new(2024, 1, 1)) do
        subscription = create(
          :subscription,
          organization:,
          customer:,
          plan:,
          external_id: "sub_chain",
          started_at: Time.current,
          subscription_at: Time.current,
          status: :active,
          billing_time: :calendar
        )

        # RS1: active, weekly, 2 cycles
        srs1 = SubscriptionRateSchedule.create!(
          organization:,
          subscription:,
          rate_schedule: rate_schedule_1,
          product_item: subscription_item,
          status: :active,
          started_at: Time.current,
          intervals_to_bill: 2
        )
        srs1.update_next_billing_date!

        # RS2: pending, monthly, 2 cycles — will activate after RS1
        SubscriptionRateSchedule.create!(
          organization:,
          subscription:,
          rate_schedule: rate_schedule_2,
          product_item: subscription_item,
          status: :pending,
          intervals_to_bill: 2
        )

        # RS3: pending, quarterly, no limit — will activate after RS2
        SubscriptionRateSchedule.create!(
          organization:,
          subscription:,
          rate_schedule: rate_schedule_3,
          product_item: subscription_item,
          status: :pending
        )
      end

      # --- RS1: weekly at 10€ ---

      # Week 1: Jan 8 — RS1 bills 10€
      travel_to(DateTime.new(2024, 1, 8, 12, 0)) do
        expect { perform_rate_schedules_billing }.to change(Invoice, :count).by(1)
      end
      expect(customer.invoices.order(:created_at).last.fees_amount_cents).to eq(1000)

      # Week 2: Jan 15 — RS1 bills 10€ (last cycle)
      travel_to(DateTime.new(2024, 1, 15, 12, 0)) do
        expect { perform_rate_schedules_billing }.to change(Invoice, :count).by(1)
      end
      expect(customer.invoices.order(:created_at).last.fees_amount_cents).to eq(1000)

      srs1 = SubscriptionRateSchedule.find_by(subscription:, rate_schedule: rate_schedule_1)
      expect(srs1.intervals_billed).to eq(2)
      expect(srs1).to be_exhausted

      # RS2 still pending — activation clock hasn't run yet
      srs2 = SubscriptionRateSchedule.find_by(subscription:, rate_schedule: rate_schedule_2)
      expect(srs2).to be_pending

      # Activation clock runs — detects RS1 end_date reached, activates RS2, terminates RS1
      travel_to(DateTime.new(2024, 1, 15, 12, 5)) do
        perform_rate_schedules_activation
      end

      srs1.reload
      expect(srs1).to be_terminated
      expect(srs1.ended_at).to be_present

      srs2.reload
      expect(srs2).to be_active
      expect(srs2.started_at).to be_present

      # --- RS2: monthly at 20€ ---

      # Feb 15 — RS2 bills 20€
      travel_to(DateTime.new(2024, 2, 15, 12, 0)) do
        expect { perform_rate_schedules_billing }.to change(Invoice, :count).by(1)
      end
      expect(customer.invoices.order(:created_at).last.fees_amount_cents).to eq(2000)

      # Mar 15 — RS2 bills 20€ (last cycle)
      travel_to(DateTime.new(2024, 3, 15, 12, 0)) do
        expect { perform_rate_schedules_billing }.to change(Invoice, :count).by(1)
      end
      expect(customer.invoices.order(:created_at).last.fees_amount_cents).to eq(2000)

      srs2.reload
      expect(srs2.intervals_billed).to eq(2)
      expect(srs2).to be_exhausted

      # Activation clock runs — detects RS2 end_date reached, activates RS3, terminates RS2
      travel_to(DateTime.new(2024, 3, 15, 12, 5)) do
        perform_rate_schedules_activation
      end

      srs2.reload
      expect(srs2).to be_terminated
      expect(srs2.ended_at).to be_present

      srs3 = SubscriptionRateSchedule.find_by(subscription:, rate_schedule: rate_schedule_3)
      expect(srs3).to be_active
      expect(srs3.started_at).to be_present

      # --- RS3: quarterly at 30€ ---

      # Jun 15 — RS3 bills 30€
      travel_to(DateTime.new(2024, 6, 15, 12, 0)) do
        expect { perform_rate_schedules_billing }.to change(Invoice, :count).by(1)
      end
      expect(customer.invoices.order(:created_at).last.fees_amount_cents).to eq(3000)

      # Sep 15 — RS3 bills 30€ (no limit, keeps going)
      travel_to(DateTime.new(2024, 9, 15, 12, 0)) do
        expect { perform_rate_schedules_billing }.to change(Invoice, :count).by(1)
      end
      expect(customer.invoices.order(:created_at).last.fees_amount_cents).to eq(3000)

      # Verify the full billing history
      expect(customer.invoices.count).to eq(6)
      amounts = customer.invoices.order(:created_at).map(&:fees_amount_cents)
      expect(amounts).to eq([1000, 1000, 2000, 2000, 3000, 3000])
    end
  end
end