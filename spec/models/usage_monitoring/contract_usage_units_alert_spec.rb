# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::ContractUsageUnitsAlert do
  subject(:alert) { create(:contract_usage_units_alert) }

  it "is stored and loaded as a usage units alert" do
    expect(alert.alert_type).to eq("usage_units")
    expect(UsageMonitoring::ContractAlert.find(alert.id)).to be_an_instance_of(described_class)
  end

  describe "validations" do
    it "requires a product" do
      alert.product = nil

      expect(alert).to be_invalid
      expect(alert.errors[:product]).to eq(["value_is_mandatory"])
    end
  end

  describe "#card_value" do
    let(:card_usage) do
      RateCardUsage.new(
        contract_rate_card: build_stubbed(:contract_rate_card),
        obligation: nil,
        rate_phase: nil,
        segments: [RateCardUsageSegment.new(billing_segment: BillingSegment.new,
          fees: [Fee.new(units: BigDecimal("3.5"), amount_cents: 120_00), Fee.new(units: 2, amount_cents: 80_00)])]
      )
    end

    it "returns the usage units of the card" do
      # one fee per pricing group
      expect(alert.card_value(card_usage)).to eq(BigDecimal("3.5") + 2)
    end
  end
end
