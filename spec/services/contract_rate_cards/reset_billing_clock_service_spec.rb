# frozen_string_literal: true

require "rails_helper"

RSpec.describe ContractRateCards::ResetBillingClockService do
  subject(:result) { described_class.call(contract_rate_card:, timestamp:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:contract) { create(:contract, :pending, organization:, customer:, started_at: Time.zone.parse("2026-09-30")) }
  let(:rate_card) { create(:rate_card, organization:) }
  # Seeded while the rate was monthly: the clock waits for the end of the first month.
  let(:contract_rate_card) do
    create(
      :contract_rate_card,
      organization:,
      contract:,
      rate_card:,
      effective_date: Date.new(2026, 9, 30),
      billing_anchor_date: Date.new(2026, 9, 30),
      next_billing_at: Time.zone.parse("2026-10-30")
    )
  end
  let(:timestamp) { contract.started_at }

  before do
    create(:rate_card_rate, organization:, rate_card:, effective_from: Time.zone.parse("2026-09-01"), billing_interval_unit: "week")
    create(:rate_phase, :contract_level, organization:, contract_rate_card:)
  end

  it "sets the clock to the billing date of the current cadence" do
    expect(result).to be_success
    expect(contract_rate_card.reload.next_billing_at).to eq(Time.zone.parse("2026-10-07"))
  end

  context "when the card has no schedule" do
    let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, next_billing_at: Time.zone.parse("2026-10-30")) }

    before { RateCardRate.where(rate_card:).delete_all }

    it "keeps the clock" do
      expect(result).to be_success
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.zone.parse("2026-10-30"))
    end
  end
end
