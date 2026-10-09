# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::RateCardRateSerializer do
  subject(:serializer) { described_class.new(rate, root_name: "rate") }

  let(:rate) { create(:rate_card_rate) }

  it "serializes the rate" do
    payload = serializer.serialize

    expect(payload[:lago_id]).to eq(rate.id)
    expect(payload[:code]).to eq(rate.code)
    expect(payload[:effective_from]).to eq(rate.effective_from.iso8601)
    expect(payload[:status]).to eq("active")
    expect(payload[:rate_model]).to eq(rate.rate_model)
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
