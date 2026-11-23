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
end
