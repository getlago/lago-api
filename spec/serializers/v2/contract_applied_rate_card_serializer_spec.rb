# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::ContractAppliedRateCardSerializer do
  subject(:payload) { described_class.new(contract_rate_card).serialize }

  let(:organization) { contract.organization }
  let(:contract) { create(:contract, external_id: "contract_001") }
  let(:rate_card) { create(:rate_card, organization:, code: "seats") }
  let(:deleted_at) { nil }
  let(:next_billing_at) { Time.zone.parse("2026-10-15T00:00:00Z") }
  let(:contract_rate_card) do
    create(
      :contract_rate_card,
      organization:,
      contract:,
      rate_card:,
      # Too precise for a Float, so rendering units as a Float fails the comparison.
      units:,
      effective_date: Date.new(2026, 10, 1),
      billing_anchor_date:,
      next_billing_at:,
      created_at: Time.zone.parse("2026-09-30T08:00:00Z"),
      updated_at: Time.zone.parse("2026-10-01T09:30:00Z"),
      deleted_at:
    )
  end
  let(:billing_anchor_date) { Date.new(2026, 10, 15) }
  let(:units) { BigDecimal("12.3456789012345678901") }
  let(:flat_payload) do
    {
      lago_id: contract_rate_card.id,
      external_contract_id: "contract_001",
      rate_card_code: "seats",
      units: BigDecimal("12.3456789012345678901"),
      scheduled_units: nil,
      scheduled_units_effective_at: nil,
      effective_date: "2026-10-01",
      billing_anchor_date: "2026-10-15",
      next_billing_at: "2026-10-15T00:00:00Z",
      created_at: "2026-09-30T08:00:00Z",
      updated_at: "2026-10-01T09:30:00Z",
      deleted_at: nil
    }
  end

  it "serializes the applied rate card, with a null deletion timestamp" do
    expect(payload).to eq(flat_payload)
  end

  context "with a future draft contract" do
    let(:contract) { create(:contract, :draft, external_id: "contract_001", started_at: Time.utc(2026, 10, 1)) }

    around { |example| travel_to(Time.utc(2026, 9, 1)) { example.run } }

    it "returns the saved starting units" do
      expect(payload).to eq(flat_payload)
    end
  end

  context "with a scheduled units change" do
    let(:timestamp) { Time.utc(2026, 11, 15) }
    let(:billing_anchor_date) { Date.new(2026, 10, 1) }

    around { |example| travel_to(timestamp) { example.run } }

    before do
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 10, 1))
      create(:contract_rate_card_term, organization:, contract_rate_card:, units: 5, effective_date: Date.new(2026, 11, 15),
        created_at: Time.utc(2026, 11, 15), application_timing: :next_billing_cycle)
    end

    it "returns current units and the scheduled quantity and time" do
      expect(payload).to eq(flat_payload.merge(billing_anchor_date: "2026-10-01", scheduled_units: 5, scheduled_units_effective_at: "2026-12-01T00:00:00Z"))
    end

    context "when the scheduled change takes effect" do
      let(:timestamp) { Time.utc(2026, 12, 1) }

      it "returns the new current units without a scheduled change" do
        expect(payload).to eq(flat_payload.merge(billing_anchor_date: "2026-10-01", units: 5))
      end
    end
  end

  context "when multiple units rows exist" do
    before do
      create(
        :contract_rate_card_term,
        organization:,
        contract_rate_card:,
        units: BigDecimal("3.25"),
        effective_date: Date.new(2026, 9, 1)
      )
    end

    it "serializes the current effective units row" do
      expect(payload).to eq(flat_payload)
    end
  end

  context "when there are no units rows" do
    let(:units) { nil }

    it "serializes null units" do
      expect(payload).to eq(flat_payload.merge(units: nil))
    end
  end

  context "when the applied rate card is deleted" do
    let(:deleted_at) { Time.zone.parse("2026-10-20T16:45:00Z") }

    it "includes the deletion timestamp" do
      expect(payload).to eq(flat_payload.merge(deleted_at: "2026-10-20T16:45:00Z"))
    end
  end

  context "with rate phases" do
    before do
      create(:rate_phase, :contract_level, organization:, contract_rate_card:, position: 1)
      create(:rate_phase, :contract_level, organization:, contract_rate_card:, position: 2)
      create(:rate_phase, :contract_level, organization:, contract_rate_card:, position: 3, deleted_at: Time.current)
    end

    it "renders no count of them" do
      expect(payload).to eq(flat_payload)
    end
  end

  # An exhausted chain must not fall back to computing a new cycle.
  context "when the billing schedule has run out" do
    before do
      contract_rate_card
      travel_to(Time.zone.parse("2026-10-01T09:30:00Z")) { contract_rate_card.update!(next_billing_at: nil) }
    end

    it "renders a null next billing time" do
      expect(payload).to eq(flat_payload.merge(next_billing_at: nil))
    end
  end
end
