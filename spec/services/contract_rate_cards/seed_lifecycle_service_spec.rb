# frozen_string_literal: true

require "rails_helper"

RSpec.describe ContractRateCards::SeedLifecycleService do
  subject(:result) { described_class.call(contract_rate_card:, billing_anchor_date:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:contract) { create(:contract, :pending, organization:, customer:, started_at: Time.zone.parse("2026-11-15")) }
  let(:contract_rate_card) do
    create(
      :contract_rate_card,
      organization:,
      contract:,
      effective_date: Date.new(2026, 10, 1),
      billing_anchor_date: Date.new(2026, 10, 1),
      next_billing_at: Time.zone.parse("2026-10-01")
    )
  end
  let(:billing_anchor_date) { nil }

  around { |example| travel_to(Time.zone.parse("2026-09-30T12:00:00Z")) { example.run } }

  it "starts the card with its contract" do
    expect(result).to be_success
    expect(contract_rate_card.reload).to have_attributes(
      effective_date: Date.new(2026, 11, 15),
      billing_anchor_date: Date.new(2026, 11, 15),
      next_billing_at: Time.zone.parse("2026-11-15")
    )
  end

  context "with an anchor of the card's own" do
    let(:billing_anchor_date) { Date.new(2026, 11, 1) }

    it "keeps it" do
      result

      expect(contract_rate_card.reload.billing_anchor_date).to eq(Date.new(2026, 11, 1))
    end
  end

  context "when the contract started in the past" do
    let(:contract) { create(:contract, :pending, organization:, customer:, started_at: Time.zone.parse("2026-08-15")) }
    let(:rate_card) { create(:rate_card, organization:) }
    let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, rate_card:) }

    before do
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.zone.parse("2026-08-01"))
      create(:rate_phase, :contract_level, organization:, contract_rate_card:)
    end

    it "waits for the billing date of the current period, its end on an arrears card" do
      result

      expect(contract_rate_card.reload.next_billing_at).to eq(Time.zone.parse("2026-10-15"))
    end
  end
end
