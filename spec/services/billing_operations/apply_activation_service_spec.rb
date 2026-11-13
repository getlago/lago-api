# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingOperations::ApplyActivationService do
  subject(:result) { described_class.call(contract:) }

  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let(:customer) { create(:customer, organization:) }
  let(:contract) { create(:contract, organization:, customer:) }
  let(:product) { create(:product, :fixed, organization:) }
  let(:rate_card) { create(:rate_card, organization:, product:, billing_timing: "arrears") }
  let(:contract_rate_card) do
    create(:contract_rate_card, organization:, contract:, rate_card:, effective_date: Date.current, billing_anchor_date: Date.current)
  end

  before do
    contract_rate_card
    create(:rate_card_rate, organization:, rate_card:, effective_from: Time.current, billing_interval_count: 1, billing_interval_unit: "month")
  end

  it "creates the initial operations for priced cards with activation causation" do
    expect { result }.to change(BillingOperation, :count).by(1)
    expect(result.billing_operations.sole.causation_type).to eq("contract_activation")
  end

  context "when product catalog is disabled" do
    let(:organization) { create(:organization) }

    it "does not create an operation" do
      expect { result }.not_to change(BillingOperation, :count)
      expect(result.billing_operations).to be_empty
    end
  end
end
