# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::RatePhaseSerializer do
  subject(:payload) { described_class.new(rate_phase).serialize }

  let(:rate_override) { nil }
  let(:deleted_at) { nil }
  let(:rate_phase) do
    build_stubbed(
      :rate_phase,
      code: "launch",
      position: 1,
      name: "Launch",
      billing_interval_cycle_count: 3,
      rate_override:,
      deleted_at:
    )
  end
  let(:flat_payload) do
    {
      lago_id: rate_phase.id,
      code: "launch",
      position: 1,
      name: "Launch",
      billing_interval_cycle_count: 3,
      deleted_at: nil,
      rate_override: nil
    }
  end

  it "serializes the phase, without a rate override" do
    expect(payload).to eq(flat_payload)
  end

  context "when the rate phase is deleted" do
    let(:deleted_at) { Time.zone.parse("2026-03-04T10:00:00Z") }

    it "includes the deletion timestamp" do
      expect(payload).to eq(flat_payload.merge(deleted_at: "2026-03-04T10:00:00Z"))
    end
  end

  context "with a rate override" do
    let(:override_deleted_at) { nil }
    let(:rate_override) do
      build_stubbed(
        :rate_override,
        rate_model: "standard",
        rate_properties: {"amount" => "10"},
        min_amount_cents: 500,
        billing_interval_count: 2,
        billing_interval_unit: "month",
        pricing_unit_conversion_rate: "0.5",
        deleted_at: override_deleted_at
      )
    end
    let(:override_payload) do
      {
        lago_id: rate_override.id,
        rate_model: "standard",
        rate_properties: {"amount" => "10"},
        min_amount_cents: 500,
        billing_interval_count: 2,
        billing_interval_unit: "month",
        pricing_unit_conversion_rate: BigDecimal("0.5"),
        deleted_at: nil
      }
    end

    it "embeds the rate override" do
      expect(payload).to eq(flat_payload.merge(rate_override: override_payload))
    end

    # Deleting a phase discards its override too, and the response renders both.
    context "when the phase and its override are deleted" do
      let(:deleted_at) { Time.zone.parse("2026-03-04T10:00:00Z") }
      let(:override_deleted_at) { deleted_at }

      it "includes both deletion timestamps" do
        expect(payload).to eq(
          flat_payload.merge(
            deleted_at: "2026-03-04T10:00:00Z",
            rate_override: override_payload.merge(deleted_at: "2026-03-04T10:00:00Z")
          )
        )
      end
    end
  end
end
