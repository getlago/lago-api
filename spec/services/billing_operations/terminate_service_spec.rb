# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingOperations::TerminateService do
  subject(:result) { described_class.call(contract:, timestamp:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, timezone: "UTC") }
  let(:started_at) { Time.utc(2026, 11, 1) }
  let(:timestamp) { Time.utc(2026, 11, 15) }
  let(:contract) do
    create(:contract, organization:, customer:, started_at:, status: :terminated, terminated_at: timestamp)
  end
  let(:product) { create(:product, :fixed, organization:) }
  let(:rate_card) do
    create(:rate_card, organization:, product:, billing_timing: "arrears", proration: true, currency: "USD")
  end
  let(:contract_rate_card) do
    create(:contract_rate_card, organization:, contract:, rate_card:, units: 1,
      effective_date: Date.new(2026, 11, 1), billing_anchor_date: Date.new(2026, 11, 1),
      next_billing_at: Time.utc(2026, 12, 1))
  end

  before do
    create(:rate_card_rate, organization:, rate_card:, effective_from: started_at,
      rate_model: "standard", rate_properties: {"amount" => "30"},
      billing_interval_count: 1, billing_interval_unit: "month")
    contract_rate_card
  end

  it "returns the final operation it creates" do
    expect(result).to be_success
    expect(result.billing_operations.sole).to have_attributes(
      action_type: "close_fixed_arrears", causation_type: "contract_termination",
      billing_at: timestamp, target_cycle_started_at: started_at
    )
    expect(contract_rate_card.reload.next_billing_at).to eq(timestamp)
  end

  context "when the contract has no rate cards" do
    let(:contract_rate_card) { nil }

    it "returns an empty operation list" do
      expect(result).to be_success
      expect(result.billing_operations).to eq([])
    end
  end
end
