# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::RateOverrideSerializer do
  subject(:payload) { described_class.new(rate_override).serialize }

  let(:rate_override) { build_stubbed(:rate_override) }
  let(:flat_payload) do
    {
      lago_id: rate_override.id,
      rate_model: "standard",
      rate_properties: {"amount" => "10"},
      min_amount_cents: 0,
      billing_interval_count: nil,
      billing_interval_unit: nil,
      pricing_unit_conversion_rate: nil,
      deleted_at: nil
    }
  end

  it "serializes the rate override, with a null deletion timestamp" do
    expect(payload).to eq(flat_payload)
  end

  context "when the rate override is deleted" do
    let(:rate_override) { build_stubbed(:rate_override, deleted_at: Time.zone.parse("2026-03-01T10:00:00Z")) }

    it "includes the deletion timestamp" do
      expect(payload).to eq(flat_payload.merge(deleted_at: "2026-03-01T10:00:00Z"))
    end
  end

  context "when the override sets every overridable field" do
    let(:rate_override) do
      build_stubbed(
        :rate_override,
        min_amount_cents: 500,
        billing_interval_count: 3,
        billing_interval_unit: "month",
        # Too precise for a Float, so rendering the rate as a Float fails the comparison.
        pricing_unit_conversion_rate: "1234567890.1234567891"
      )
    end

    it "renders the overridden values" do
      expect(payload).to eq(
        flat_payload.merge(
          min_amount_cents: 500,
          billing_interval_count: 3,
          billing_interval_unit: "month",
          pricing_unit_conversion_rate: BigDecimal("1234567890.1234567891")
        )
      )
    end
  end

  context "with graduated tiers" do
    let(:rate_override) do
      build_stubbed(
        :rate_override,
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
