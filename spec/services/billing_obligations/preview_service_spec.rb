# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingObligations::PreviewService do
  subject(:result) { described_class.call(contracts: [contract], start_on: nil, end_on: Date.new(2026, 2, 1)) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, timezone: "UTC") }
  let(:contract) { create(:contract, organization:, customer:, started_at: Time.utc(2026, 1, 1), ended_at:) }
  let(:ended_at) { nil }
  let(:monthly) { create(:rate_card, organization:) }
  let(:yearly) { create(:rate_card, organization:) }
  let(:unpriced) { create(:rate_card, organization:) }

  before do
    [monthly, yearly, unpriced].each do |rate_card|
      create(:contract_rate_card, organization:, contract:, rate_card:, effective_date: Date.new(2026, 1, 1),
        billing_anchor_date: Date.new(2026, 1, 1), next_billing_at: Time.utc(2026, 12, 1))
    end
    create(:rate_card_rate, organization:, rate_card: monthly, effective_from: contract.started_at)
    create(:rate_card_rate, organization:, rate_card: yearly, effective_from: contract.started_at, billing_interval_unit: "year")
  end

  it "previews priced cards before their stored clocks and returns the earliest upcoming billing" do
    expect(result).to be_success
    expect(result.billing_obligations.map { it.contract_rate_card.rate_card }).to match_array([monthly, monthly, yearly])
    expect(result.next_billing_at).to eq(Time.utc(2026, 3, 1))
  end

  context "when the contract ended during the window" do
    let(:ended_at) { Time.utc(2026, 1, 20) }

    it "stops both cards at the contract end and has no next billing" do
      expect(result.billing_obligations.map { it.obligation.segments.sole.ended_at }).to eq([ended_at, ended_at])
      expect(result.next_billing_at).to be_nil
    end
  end
end
