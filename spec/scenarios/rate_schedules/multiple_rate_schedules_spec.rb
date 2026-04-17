# frozen_string_literal: true

require "rails_helper"

describe "Rate Schedules Multiple Rate Schedules" do
  include_context "with rate schedule billing"

  let(:billing_interval_unit) { "month" }

  describe "rate schedule succession on the same product item" do
    # Subscription fee with 3 rate schedules chained:
    #   RS1: 10€, weekly,  2 cycles  (Jan 1 → Jan 8, Jan 8 → Jan 15)
    #   RS2: 20€, monthly, 2 cycles  (Jan 15 → Feb 15, Feb 15 → Mar 15)
    #   RS3: 30€, quarterly, 2 cycles (Mar 15 → Jun 15, Jun 15 → Sep 15)
    #
    # All cycles are created upfront — the billing query naturally picks up
    # the right cycles at the right time based on to_datetime dates.

    let(:rate_schedule_1) do
      create(:rate_schedule, organization:, plan_product_item:, product_item: subscription_item,
        charge_model: "standard", billing_interval_unit: "week", billing_interval_count: 1,
        amount_currency: "EUR", properties: {"amount" => "10.00"}, position: 0)
    end

    let(:rate_schedule_2) do
      create(:rate_schedule, organization:, plan_product_item:, product_item: subscription_item,
        charge_model: "standard", billing_interval_unit: "month", billing_interval_count: 1,
        amount_currency: "EUR", properties: {"amount" => "20.00"}, position: 1)
    end

    let(:rate_schedule_3) do
      create(:rate_schedule, organization:, plan_product_item:, product_item: subscription_item,
        charge_model: "standard", billing_interval_unit: "month", billing_interval_count: 3,
        amount_currency: "EUR", properties: {"amount" => "30.00"}, position: 2)
    end

    let(:rate_schedule) { rate_schedule_1 }

    before do
      rate_schedule_2
      rate_schedule_3
    end

    it "chains through rate schedules as each one exhausts its cycles" do # rubocop:disable RSpec/ExampleLength
      travel_to(DateTime.new(2024, 1, 1)) do
        subscription = create(:subscription, organization:, customer:, plan:,
          external_id: "sub_chain", started_at: Time.current, subscription_at: Time.current,
          status: :active, billing_time: :calendar)

        # RS1: weekly, 2 cycles from Jan 1
        create(:subscription_rate_schedule, :with_cycles,
          organization:, subscription:, rate_schedule: rate_schedule_1,
          product_item: subscription_item, status: :active,
          started_at: Time.current, cycles_count: 2)

        # RS2: monthly, 2 cycles from Jan 15 (chained after RS1)
        srs2 = create(:subscription_rate_schedule,
          organization:, subscription:, rate_schedule: rate_schedule_2,
          product_item: subscription_item, status: :active,
          started_at: DateTime.new(2024, 1, 15))
        create(:subscription_rate_schedule_cycle, organization:, subscription_rate_schedule: srs2,
          cycle_index: 0, from_datetime: DateTime.new(2024, 1, 15))
        create(:subscription_rate_schedule_cycle, organization:, subscription_rate_schedule: srs2,
          cycle_index: 1, from_datetime: DateTime.new(2024, 2, 15))

        # RS3: quarterly, 2 cycles from Mar 15 (chained after RS2)
        srs3 = create(:subscription_rate_schedule,
          organization:, subscription:, rate_schedule: rate_schedule_3,
          product_item: subscription_item, status: :active,
          started_at: DateTime.new(2024, 3, 15))
        create(:subscription_rate_schedule_cycle, organization:, subscription_rate_schedule: srs3,
          cycle_index: 0, from_datetime: DateTime.new(2024, 3, 15))
        create(:subscription_rate_schedule_cycle, organization:, subscription_rate_schedule: srs3,
          cycle_index: 1, from_datetime: DateTime.new(2024, 6, 15))
      end

      # --- RS1: weekly at 10€ ---

      # Week 1: Jan 8
      travel_to(DateTime.new(2024, 1, 8, 12, 0)) do
        expect { perform_rate_schedules_billing }.to change(Invoice, :count).by(1)
      end
      expect(customer.invoices.order(:created_at).last.fees_amount_cents).to eq(1000)

      # Week 2: Jan 15
      travel_to(DateTime.new(2024, 1, 15, 12, 0)) do
        expect { perform_rate_schedules_billing }.to change(Invoice, :count).by(1)
      end
      expect(customer.invoices.order(:created_at).last.fees_amount_cents).to eq(1000)

      # --- RS2: monthly at 20€ (naturally picked up by dates) ---

      # Feb 15
      travel_to(DateTime.new(2024, 2, 15, 12, 0)) do
        expect { perform_rate_schedules_billing }.to change(Invoice, :count).by(1)
      end
      expect(customer.invoices.order(:created_at).last.fees_amount_cents).to eq(2000)

      # Mar 15
      travel_to(DateTime.new(2024, 3, 15, 12, 0)) do
        expect { perform_rate_schedules_billing }.to change(Invoice, :count).by(1)
      end
      expect(customer.invoices.order(:created_at).last.fees_amount_cents).to eq(2000)

      # --- RS3: quarterly at 30€ (naturally picked up by dates) ---

      # Jun 15
      travel_to(DateTime.new(2024, 6, 15, 12, 0)) do
        expect { perform_rate_schedules_billing }.to change(Invoice, :count).by(1)
      end
      expect(customer.invoices.order(:created_at).last.fees_amount_cents).to eq(3000)

      # Sep 15
      travel_to(DateTime.new(2024, 9, 15, 12, 0)) do
        expect { perform_rate_schedules_billing }.to change(Invoice, :count).by(1)
      end
      expect(customer.invoices.order(:created_at).last.fees_amount_cents).to eq(3000)

      # Full billing history
      expect(customer.invoices.count).to eq(6)
      amounts = customer.invoices.order(:created_at).map(&:fees_amount_cents)
      expect(amounts).to eq([1000, 1000, 2000, 2000, 3000, 3000])
    end
  end
end
