# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::ContractUsageSerializer do
  subject(:payload) { described_class.new(usage).serialize }

  let(:customer) { build_stubbed(:customer, external_id: "customer_001", currency: "EUR") }
  let(:contract) { build_stubbed(:contract, customer:, external_id: "contract_001") }
  let(:rate_card_usages) { [] }
  let(:usage) do
    Contracts::CurrentUsageService::Result.new.tap do |result|
      result.contract = contract
      result.rate_card_usages = rate_card_usages
      result.amount_cents = rate_card_usages.sum(&:amount_cents)
      result.taxes_amount_cents = rate_card_usages.sum(&:taxes_amount_cents)
      result.total_amount_cents = result.amount_cents + result.taxes_amount_cents
    end
  end
  let(:flat_payload) do
    {
      external_contract_id: "contract_001",
      external_customer_id: "customer_001",
      currency: "EUR",
      amount_cents: 0,
      taxes_amount_cents: 0,
      total_amount_cents: 0,
      rate_cards: []
    }
  end

  it "serializes a contract without usage" do
    expect(payload).to eq(flat_payload)
  end

  context "with a rate card usage" do
    let(:contract_rate_card) { build_stubbed(:contract_rate_card, contract:) }
    let(:rate_card_usage) do
      RateCardUsage.new(
        contract_rate_card:,
        billing_segment: build_stubbed(:billing_segment, contract:, contract_rate_card:),
        rate_phase: nil,
        fees: [build_stubbed(:fee, amount_cents: 700, taxes_amount_cents: 140)]
      )
    end
    let(:rate_card_usages) { [rate_card_usage] }

    it "renders the totals and each card as its own serializer does" do
      expect(payload).to eq(
        flat_payload.merge(
          amount_cents: 700,
          taxes_amount_cents: 140,
          total_amount_cents: 840,
          rate_cards: [V2::RateCardUsageSerializer.new(rate_card_usage).serialize]
        )
      )
    end

    context "with the usec_timestamps include of a v2 render" do
      subject(:payload) { described_class.new(usage, includes: %i[usec_timestamps]).serialize }

      it "renders each card's window to the microsecond too" do
        expect(payload[:rate_cards]).to eq([V2::RateCardUsageSerializer.new(rate_card_usage, includes: %i[usec_timestamps]).serialize])
        expect(payload[:rate_cards].sole.values_at(:from_datetime, :to_datetime)).to all(match(/\.\d{6}Z\z/))
      end
    end
  end
end
