# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::ContractUsageAmountAlert do
  subject(:alert) { create(:contract_usage_amount_alert) }

  it "is stored and loaded as a usage amount alert" do
    expect(alert.alert_type).to eq("usage_amount")
    expect(UsageMonitoring::ContractAlert.find(alert.id)).to be_an_instance_of(described_class)
  end

  describe "validations" do
    it "covers the whole contract without a product" do
      expect(alert).to have_attributes(product: nil, product_filter: nil)
      expect(alert).to be_valid
    end
  end

  describe "#card_value" do
    let(:card_usage) do
      RateCardUsage.new(
        contract_rate_card: build_stubbed(:contract_rate_card),
        obligation: nil,
        rate_phase: nil,
        segments: [RateCardUsageSegment.new(billing_segment: BillingSegment.new,
          fees: [Fee.new(units: 3, amount_cents: 120_00), Fee.new(units: 2, amount_cents: 80_00)])]
      )
    end

    it "returns the amount of the card before tax, in cents" do
      # one fee per pricing group
      expect(alert.card_value(card_usage)).to eq(BigDecimal(120_00 + 80_00))
    end
  end
end
