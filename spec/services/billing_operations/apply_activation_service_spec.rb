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

  it "initializes the cursor for priced cards without creating operations" do
    expect { result }.not_to change(BillingOperation, :count)
    expect(contract.applied_rate_cards.sole.reload.next_billing_at).to be_present
    expect(BillingOperation.count).to eq(0)
  end

  context "when product catalog is disabled" do
    let(:organization) { create(:organization) }

    it "does not create an operation" do
      expect { result }.not_to change(BillingOperation, :count)
      expect(BillingOperation.count).to eq(0)
    end
  end
end
