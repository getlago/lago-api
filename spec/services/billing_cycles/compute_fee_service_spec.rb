# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingCycles::ComputeFeeService do
  subject(:result) { described_class.call(billing_cycle:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:product_item) { create(:product_item, :fixed, organization:) }
  let(:rate_card) { create(:rate_card, organization:, product_item:, currency: "USD", proration:) }
  let(:proration) { "full" }
  let(:subscription) { create(:subscription, organization:, customer:, plan:) }
  let(:subscription_product_item) do
    create(:subscription_product_item, organization:, subscription:, product_item:,
      billing_anchor_date: Date.new(2026, 6, 1), started_at: Time.utc(2026, 6, 1), next_billing_at: Time.utc(2026, 7, 1))
  end

  let!(:plan_product_item) { create(:plan_product_item, organization:, plan:, product_item:, rate_card:, units: 1) }
  let!(:rate) do
    create(:rate_card_rate, organization:, rate_card:, effective_datetime: Time.utc(2026, 1, 1),
      rate_model: "standard", rate_properties: {"amount" => "20"}, billing_interval_unit: "month", billing_interval_count: 1)
  end

  let(:billing_cycle) do
    create(:billing_cycle, organization:, subscription:, subscription_product_item:,
      billing_at: Time.utc(2026, 7, 1), period_from:, period_to:)
  end

  context "full period" do
    let(:period_from) { Time.utc(2026, 6, 1) }
    let(:period_to) { Time.utc(2026, 6, 30).end_of_day }

    it "charges the full amount" do
      expect(result.fee.amount_cents).to eq(2000) # $20.00
      expect(result.fee.amount_currency).to eq("USD")
      expect(result.fee.fee_type).to eq("product_item")
      expect(result.fee.rate_card_rate).to eq(rate)
    end
  end

  context "partial period (proration full)" do
    let(:period_from) { Time.utc(2026, 6, 8) }       # 23 days of June
    let(:period_to) { Time.utc(2026, 6, 30).end_of_day }

    it "prorates by day count" do
      # 23/30 * $20.00 = $15.33
      expect(result.fee.amount_cents).to eq(1533)
    end
  end

  context "partial period (proration none)" do
    let(:proration) { "none" }
    let(:period_from) { Time.utc(2026, 6, 8) }
    let(:period_to) { Time.utc(2026, 6, 30).end_of_day }

    it "charges the full amount despite the partial period" do
      expect(result.fee.amount_cents).to eq(2000)
    end
  end
end
