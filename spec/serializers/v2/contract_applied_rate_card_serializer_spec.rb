# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::ContractAppliedRateCardSerializer do
  subject(:payload) { described_class.new(contract_rate_card).serialize }

  let(:organization) { contract.organization }
  let(:contract) { create(:contract, external_id: "contract_001") }
  let(:rate_card) { create(:rate_card, organization:, code: "seats") }
  let(:deleted_at) { nil }
  let(:contract_rate_card) do
    create(
      :contract_rate_card,
      organization:,
      contract:,
      rate_card:,
      # Too precise for a Float, so rendering units as a Float fails the comparison.
      units: BigDecimal("12.3456789012345678901"),
      effective_date: Date.new(2026, 10, 1),
      billing_anchor_date: Date.new(2026, 10, 15),
      next_billing_at: Time.zone.parse("2026-10-15T00:00:00Z"),
      created_at: Time.zone.parse("2026-09-30T08:00:00Z"),
      updated_at: Time.zone.parse("2026-10-01T09:30:00Z"),
      deleted_at:
    )
  end
  let(:flat_payload) do
    {
      lago_id: contract_rate_card.id,
      external_contract_id: "contract_001",
      rate_card_code: "seats",
      units: BigDecimal("12.3456789012345678901"),
      effective_date: "2026-10-01",
      billing_anchor_date: "2026-10-15",
      next_billing_at: "2026-10-15T00:00:00Z",
      rate_phases_count: 0,
      created_at: "2026-09-30T08:00:00Z",
      updated_at: "2026-10-01T09:30:00Z",
      deleted_at: nil
    }
  end

  it "serializes the applied rate card, with a null deletion timestamp" do
    expect(payload).to eq(flat_payload)
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

    it "counts the kept phases only" do
      expect(payload).to eq(flat_payload.merge(rate_phases_count: 2))
    end
  end

  # A finished schedule has no next instant: the card is created with one, then its clock is cleared.
  context "when the billing schedule has run out" do
    before do
      travel_to(Time.zone.parse("2026-10-20T16:45:00Z")) { contract_rate_card.update!(next_billing_at: nil) }
    end

    it "renders a null next billing time" do
      expect(payload).to eq(flat_payload.merge(next_billing_at: nil, updated_at: "2026-10-20T16:45:00Z"))
    end
  end
end
