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
end
