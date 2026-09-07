# frozen_string_literal: true

require "rails_helper"

RSpec.describe ContractRateCards::DestroyService do
  subject(:result) { described_class.call(contract_rate_card:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:contract) { create(:contract, :pending, organization:, customer:) }
  let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:) }

  it "discards the card and its phases and overrides" do
    override = create(:rate_override, organization:)
    phase = create(:rate_phase, :contract_level, organization:, contract_rate_card:, rate_override: override)

    expect(result).to be_success
    expect(contract_rate_card.reload.discarded?).to be(true)
    expect(phase.reload.discarded?).to be(true)
    expect(override.reload.discarded?).to be(true)
  end

  context "when the contract is locked (active)" do
    let(:contract) { create(:contract, organization:, customer:) }

    it "fails with a contract_locked error" do
      expect(result).not_to be_success
      expect(result.error.messages[:contract]).to eq(["contract_locked"])
    end
  end

  context "when the card is missing" do
    let(:contract_rate_card) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("applied_rate_card")
    end
  end
end
