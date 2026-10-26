# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::RateCardRateSerializer do
  subject(:payload) { described_class.new(rate).serialize }

  # The status is derived from the current time, and the factory's effective_from follows it.
  around { |example| travel_to(Time.zone.parse("2026-06-15T10:30:00Z")) { example.run } }

  let(:rate_card) { create(:rate_card, code: "standard") }
  let(:rate) { create(:rate_card_rate, organization: rate_card.organization, rate_card:, code: "monthly_rate") }
  let(:flat_payload) do
    {
      lago_id: rate.id,
      code: "monthly_rate",
      rate_card_code: "standard",
      effective_from: "2026-06-15T00:00:00Z",
      status: "active",
      rate_model: "standard",
      rate_properties: {"amount" => "10"},
      min_amount_cents: 0,
      billing_interval_count: 1,
      billing_interval_unit: "month",
      applied_pricing_unit_conversion_rate: nil,
      created_at: "2026-06-15T10:30:00Z",
      updated_at: "2026-06-15T10:30:00Z",
      deleted_at: nil
    }
  end

  it "serializes the active rate, with a null deletion timestamp" do
    expect(payload).to eq(flat_payload)
  end

  context "when the rate is deleted" do
    let(:rate) do
      create(:rate_card_rate, organization: rate_card.organization, rate_card:, code: "monthly_rate", deleted_at: Time.zone.parse("2026-06-14T08:00:00Z"))
    end

    it "includes the deletion timestamp" do
      expect(payload).to eq(flat_payload.merge(deleted_at: "2026-06-14T08:00:00Z"))
    end

    # As a delayed webhook or log reads it, once its rate card is deleted too.
    context "with its rate card deleted" do
      before do
        create(:rate_card, organization: rate_card.organization, code: "other_card")
        rate_card.discard!
      end

      it "still renders the code of its own rate card" do
        expect(described_class.new(RateCardRate.with_discarded.find(rate.id)).serialize).to eq(flat_payload.merge(deleted_at: "2026-06-14T08:00:00Z"))
      end
    end
  end

  context "with graduated tiers" do
    let(:rate) do
      create(
        :rate_card_rate,
        organization: rate_card.organization,
        rate_card:,
        code: "monthly_rate",
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
      expect(payload).to eq(
        flat_payload.merge(
          rate_model: "graduated",
          rate_properties: {
            "graduated_ranges" => [
              {"to_value" => "10", "flat_amount" => "0", "per_unit_amount" => "1"},
              {"to_value" => nil, "flat_amount" => "0", "per_unit_amount" => "0.5"}
            ]
          }
        )
      )
    end
  end
end
