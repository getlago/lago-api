# frozen_string_literal: true

require "rails_helper"

RSpec.describe ContractRateCards::UnitsAtService do
  subject(:result) { described_class.call(contract_rate_card:, timestamp:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, timezone: "America/New_York") }
  let(:contract) { create(:contract, organization:, customer:) }
  let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, units: 8, effective_date: Date.new(2026, 9, 1)) }
  let(:timestamp) { Time.utc(2026, 9, 15, 12, 30) }

  before do
    create(:contract_rate_card_term, organization:, contract_rate_card:, units: 5,
      effective_date: nil, effective_at: Time.utc(2026, 9, 15, 12, 30))
    create(:contract_rate_card_term, organization:, contract_rate_card:, units: 10,
      effective_date: nil, effective_at: Time.utc(2026, 9, 15, 13))
  end

  it "selects the change at its exact instant and excludes later changes" do
    expect(result.units).to eq(5)
  end

  context "when before the timestamped change" do
    let(:timestamp) { Time.utc(2026, 9, 15, 12, 29, 59) }

    it "uses the earlier quantity" do
      expect(result.units).to eq(8)
    end
  end

  context "when before the customer's local start day" do
    let(:timestamp) { Time.utc(2026, 9, 1, 3, 59, 59) }

    it "does not apply the legacy date in UTC" do
      expect(result.units).to be_nil
    end
  end

  context "with a preloaded association" do
    before { contract_rate_card.terms.load }

    it "uses the same ordering without another terms query" do
      queries = capture_sql { expect(result.units).to eq(5) }
      expect(queries.grep(/FROM "contract_rate_cards_terms"/i)).to be_empty
    end
  end
end
