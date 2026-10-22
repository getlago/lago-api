# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::RateCardRateSerializer do
  subject(:serializer) { described_class.new(rate, root_name: "rate") }

  let(:rate) { create(:rate_card_rate) }

  it "serializes the rate" do
    payload = serializer.serialize

    expect(payload[:lago_id]).to eq(rate.id)
    expect(payload[:code]).to eq(rate.code)
    expect(payload[:rate_card_code]).to eq(rate.rate_card.code)
    expect(payload[:effective_from]).to eq(rate.effective_from.iso8601)
    expect(payload[:status]).to eq("active")
    expect(payload[:rate_model]).to eq(rate.rate_model)
  end

  context "when the rate and its card are discarded before serialization" do
    let(:organization) { create(:organization) }
    let(:rate_card) { create(:rate_card, organization:, code: "discarded-card") }
    let(:rate) { create(:rate_card_rate, organization:, rate_card:) }
    let(:other_rate_card) { create(:rate_card, organization: rate.organization, code: "other-card") }

    it "serializes the code of its own discarded parent" do
      other_rate_card
      rate.discard
      rate_card.discard
      delayed_rate = RateCardRate.with_discarded.find(rate.id)

      expect(described_class.new(delayed_rate, root_name: "rate").serialize[:rate_card_code]).to eq("discarded-card")
    end
  end

  context "with graduated tiers" do
    let(:rate) do
      create(
        :rate_card_rate,
        rate_model: "graduated",
        rate_properties: {
          "graduated_ranges" => [
            {"from_value" => 0, "to_value" => 10, "flat_amount" => "0", "per_unit_amount" => "1"},
            {"from_value" => 10, "to_value" => nil, "flat_amount" => "0", "per_unit_amount" => "0.5"}
          ]
        }
      )
    end

    it "shows each tier by its upper bound only" do
      ranges = serializer.serialize[:rate_properties]["graduated_ranges"]

      expect(ranges.map { it["to_value"] }).to eq(["10", nil])
      expect(ranges.map(&:keys)).to all(eq(%w[to_value flat_amount per_unit_amount]))
    end
  end
end
