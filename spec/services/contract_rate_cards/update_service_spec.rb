# frozen_string_literal: true

require "rails_helper"

RSpec.describe ContractRateCards::UpdateService do
  subject(:result) { described_class.call(contract_rate_card:, params:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:contract) { create(:contract, :pending, organization:, customer:) }
  let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, units: 5) }
  let(:params) { {units: "20"} }

  it "updates the units while the contract is pending" do
    expect(result).to be_success
    expect(result.contract_rate_card.reload.units).to eq(20)
  end

  context "when a billing_anchor_date is provided" do
    let(:params) { {billing_anchor_date: "2026-05-01"} }

    it "updates the anchor" do
      expect(result).to be_success
      expect(result.contract_rate_card.reload.billing_anchor_date).to eq(Date.new(2026, 5, 1))
    end
  end

  context "when the anchor moves on a card with a rate" do
    let(:contract) { create(:contract, :pending, organization:, customer:, started_at: Time.zone.parse("2026-11-01")) }
    let(:rate_card) { create(:rate_card, organization:) }
    let(:contract_rate_card) do
      create(
        :contract_rate_card,
        organization:,
        contract:,
        rate_card:,
        effective_date: Date.new(2026, 11, 1),
        billing_anchor_date: Date.new(2026, 11, 1),
        next_billing_at: Time.zone.parse("2026-12-01")
      )
    end
    let(:params) { {billing_anchor_date: "2026-11-15"} }

    around { |example| travel_to(Time.zone.parse("2026-09-30T12:00:00Z")) { example.run } }

    before do
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.zone.parse("2026-09-01"))
      create(:rate_phase, :contract_level, organization:, contract_rate_card:)
    end

    it "bills the stub up to the new anchor instead of the old one" do
      expect(result).to be_success
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.zone.parse("2026-11-15"))
    end
  end

  context "when the clock activated the contract since it was loaded" do
    before do
      contract_rate_card
      Contract.where(id: contract.id).update_all(status: :active) # rubocop:disable Rails/SkipsModelValidations
    end

    it "fails with a contract_locked error" do
      expect(result.error.messages[:contract]).to eq(["contract_locked"])
      expect(contract_rate_card.reload.units).to eq(5)
    end
  end

  context "when the billing_anchor_date is malformed" do
    let(:params) { {billing_anchor_date: "nope"} }

    it "fails with an invalid value error" do
      expect(result).not_to be_success
      expect(result.error.messages[:billing_anchor_date]).to eq(["value_is_invalid"])
    end
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
