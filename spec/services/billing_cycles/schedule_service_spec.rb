# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingCycles::ScheduleService do
  subject(:result) { described_class.call(subscription_product_item:, up_to:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:product_item) { create(:product_item, organization:) }
  let(:rate_card) { create(:rate_card, organization:, product_item:, billing_timing: "arrears") }
  let(:subscription) { create(:subscription, customer:, plan:) }

  let(:billing_anchor_date) { Date.new(2026, 2, 1) }
  let(:started_at) { Time.utc(2026, 1, 1) }       # started before the periods being billed
  let(:next_billing_at) { Time.utc(2026, 3, 1) }  # bills the Feb period
  let(:subscription_product_item) do
    create(:subscription_product_item, organization:, subscription:, product_item:, billing_anchor_date:, started_at:, next_billing_at:)
  end

  let!(:plan_product_item) { create(:plan_product_item, organization:, plan:, product_item:, rate_card:) }
  let!(:rate) do
    create(:rate_card_rate, organization:, rate_card:,
      effective_datetime: Time.utc(2026, 1, 1), billing_interval_unit: "month", billing_interval_count: 1)
  end

  context "when one period is due" do
    let(:up_to) { Time.utc(2026, 3, 15) }

    it "creates a pending cycle for the closed period and advances the clock" do
      expect { result }.to change(BillingCycle, :count).by(1)

      cycle = result.billing_cycles.sole
      expect(cycle).to be_pending
      expect(cycle.billing_at).to eq(Time.utc(2026, 3, 1))
      expect(cycle.period_from).to eq(Time.utc(2026, 2, 1))
      expect(cycle.period_to).to match_datetime(Time.utc(2026, 2, 28, 23, 59, 59))

      expect(subscription_product_item.reload.next_billing_at).to eq(Time.utc(2026, 4, 1))
    end
  end

  context "when the subscription started mid-cycle" do
    let(:started_at) { Time.utc(2026, 2, 15) }
    let(:up_to) { Time.utc(2026, 3, 15) }

    it "bills only the remainder of the first period, not the whole month" do
      cycle = result.billing_cycles.sole

      expect(cycle.period_from).to eq(Time.utc(2026, 2, 15))
      expect(cycle.period_to).to match_datetime(Time.utc(2026, 2, 28, 23, 59, 59))
    end
  end

  context "when the clock is behind by several periods (catch-up)" do
    let(:up_to) { Time.utc(2026, 4, 15) }

    it "emits one cycle per missed period and catches the clock up" do
      expect { result }.to change(BillingCycle, :count).by(2)

      expect(result.billing_cycles.map(&:billing_at)).to eq([Time.utc(2026, 3, 1), Time.utc(2026, 4, 1)])
      expect(result.billing_cycles.map(&:period_from)).to eq([Time.utc(2026, 2, 1), Time.utc(2026, 3, 1)])
      expect(subscription_product_item.reload.next_billing_at).to eq(Time.utc(2026, 5, 1))
    end
  end

  context "when nothing is due yet" do
    let(:next_billing_at) { Time.utc(2026, 5, 1) }
    let(:up_to) { Time.utc(2026, 4, 15) }

    it "creates no cycle and leaves the clock untouched" do
      expect { result }.not_to change(BillingCycle, :count)
      expect(subscription_product_item.reload.next_billing_at).to eq(Time.utc(2026, 5, 1))
    end
  end

  context "when there is no active rate" do
    let(:up_to) { Time.utc(2026, 3, 15) }
    let!(:rate) { create(:rate_card_rate, organization:, rate_card:, effective_datetime: Time.utc(2027, 1, 1)) }

    it "does not schedule or advance (left for retry)" do
      expect { result }.not_to change(BillingCycle, :count)
      expect(subscription_product_item.reload.next_billing_at).to eq(Time.utc(2026, 3, 1))
    end
  end
end
